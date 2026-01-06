#include "../llx_tool_templates.h"
#include "llx_tool_families.h"

#include <cctype>
#include <cstdlib>

#include <nlohmann/json.hpp>

static std::string llx_to_lower_copy(std::string s) {
    for (auto &c : s) c = (char) std::tolower((unsigned char) c);
    return s;
}

static bool llx_contains_ci(const std::string &hay, const std::string &needle) {
    if (needle.empty()) return true;
    return llx_to_lower_copy(hay).find(llx_to_lower_copy(needle)) != std::string::npos;
}

bool llx_is_functiongemma_family(const std::string &model_name) {
    return llx_contains_ci(model_name, "functiongemma") || llx_contains_ci(model_name, "gemma");
}

static std::string llx_trim_copy(const std::string &s) {
    size_t b = s.find_first_not_of(" \t\r\n");
    if (b == std::string::npos) return "";
    size_t e = s.find_last_not_of(" \t\r\n");
    return s.substr(b, e - b + 1);
}

static bool llx_starts_with_at(const std::string &s, size_t pos, const std::string &prefix) {
    return pos + prefix.size() <= s.size() && s.compare(pos, prefix.size(), prefix) == 0;
}

static void llx_skip_ws(const std::string &s, size_t &i) {
    while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) i++;
}

static std::string llx_parse_key_token(const std::string &s, size_t &i) {
    llx_skip_ws(s, i);
    if (i >= s.size()) return "";
    // allow quoted key
    if (s[i] == '"' || s[i] == '\'') {
        char q = s[i++];
        std::string out;
        while (i < s.size() && s[i] != q) {
            if (s[i] == '\\' && i + 1 < s.size()) {
                out.push_back(s[i + 1]);
                i += 2;
            } else {
                out.push_back(s[i++]);
            }
        }
        if (i < s.size() && s[i] == q) i++;
        return out;
    }
    // unquoted key: read until ':' or whitespace/comma/brace
    size_t b = i;
    while (i < s.size()) {
        char c = s[i];
        if (c == ':' || c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == ',' || c == '}' || c == ']') break;
        i++;
    }
    return llx_trim_copy(s.substr(b, i - b));
}

static nlohmann::ordered_json llx_parse_functiongemma_value(const std::string &s, size_t &i, int depth);

static nlohmann::ordered_json llx_parse_functiongemma_object(const std::string &s, size_t &i, int depth) {
    using json = nlohmann::ordered_json;
    json obj = json::object();
    if (depth > 16) return obj;
    // assume current char is '{'
    if (i < s.size() && s[i] == '{') i++;
    for (;;) {
        llx_skip_ws(s, i);
        if (i >= s.size()) break;
        if (s[i] == '}') { i++; break; }

        std::string key = llx_parse_key_token(s, i);
        llx_skip_ws(s, i);
        if (i < s.size() && s[i] == ':') i++;
        llx_skip_ws(s, i);
        json val = llx_parse_functiongemma_value(s, i, depth + 1);
        if (!key.empty()) obj[key] = val;

        llx_skip_ws(s, i);
        if (i < s.size() && s[i] == ',') { i++; continue; }
        if (i < s.size() && s[i] == '}') { i++; break; }
        // tolerate missing comma by continuing
    }
    return obj;
}

static nlohmann::ordered_json llx_parse_functiongemma_array(const std::string &s, size_t &i, int depth) {
    using json = nlohmann::ordered_json;
    json arr = json::array();
    if (depth > 16) return arr;
    if (i < s.size() && s[i] == '[') i++;
    for (;;) {
        llx_skip_ws(s, i);
        if (i >= s.size()) break;
        if (s[i] == ']') { i++; break; }
        arr.push_back(llx_parse_functiongemma_value(s, i, depth + 1));
        llx_skip_ws(s, i);
        if (i < s.size() && s[i] == ',') { i++; continue; }
        if (i < s.size() && s[i] == ']') { i++; break; }
    }
    return arr;
}

static nlohmann::ordered_json llx_parse_functiongemma_value(const std::string &s, size_t &i, int depth) {
    using json = nlohmann::ordered_json;
    llx_skip_ws(s, i);
    if (i >= s.size()) return json();

    // <escape>STRING<escape>
    const std::string esc = "<escape>";
    if (llx_starts_with_at(s, i, esc)) {
        i += esc.size();
        size_t j = s.find(esc, i);
        std::string val = (j == std::string::npos) ? s.substr(i) : s.substr(i, j - i);
        i = (j == std::string::npos) ? s.size() : (j + esc.size());
        return val;
    }

    // nested object/array
    if (s[i] == '{') return llx_parse_functiongemma_object(s, i, depth);
    if (s[i] == '[') return llx_parse_functiongemma_array(s, i, depth);

    // quoted string
    if (s[i] == '"' || s[i] == '\'') {
        char q = s[i++];
        std::string out;
        while (i < s.size() && s[i] != q) {
            if (s[i] == '\\' && i + 1 < s.size()) {
                out.push_back(s[i + 1]);
                i += 2;
            } else {
                out.push_back(s[i++]);
            }
        }
        if (i < s.size() && s[i] == q) i++;
        return out;
    }

    // bare token until comma/brace/bracket
    size_t b = i;
    while (i < s.size()) {
        char c = s[i];
        if (c == ',' || c == '}' || c == ']' || c == '\r' || c == '\n') break;
        i++;
    }
    std::string tok = llx_trim_copy(s.substr(b, i - b));
    if (tok == "true") return true;
    if (tok == "false") return false;
    if (tok == "null") return json();

    // number?
    if (!tok.empty()) {
        char *endp = nullptr;
        double d = std::strtod(tok.c_str(), &endp);
        if (endp && endp != tok.c_str() && *endp == '\0') {
            // keep int if possible
            long long ll = (long long) d;
            if ((double) ll == d) return ll;
            return d;
        }
    }
    return tok;
}

std::vector<common_chat_tool_call> llx_parse_functiongemma_tool_calls(const std::string &text) {
    using json = nlohmann::ordered_json;
    std::vector<common_chat_tool_call> out;
    const std::string start = "<start_function_call>";
    const std::string end = "<end_function_call>";
    size_t pos = 0;
    int idx = 0;
    while (true) {
        size_t s = text.find(start, pos);
        if (s == std::string::npos) break;
        size_t a = s + start.size();
        size_t e = text.find(end, a);
        bool partial = false;
        if (e == std::string::npos) {
            // tolerate partial generation (e.g. missing <end_function_call>)
            e = text.size();
            partial = true;
        }
        std::string inner = llx_trim_copy(text.substr(a, e - a));

        // expected: call:NAME{...} (but be tolerant: "callNAME{...}" or "call NAME{...}")
        // We only accept a call that starts with "call" after trimming.
        if (inner.rfind("call", 0) != 0) {
            pos = partial ? e : (e + end.size());
            if (partial) break;
            continue;
        }
        size_t name_b = 4;
        if (name_b < inner.size() && inner[name_b] == ':') name_b++;
        while (name_b < inner.size() && std::isspace((unsigned char) inner[name_b])) name_b++;
        size_t brace = inner.find('{', name_b);
        if (brace == std::string::npos) {
            pos = partial ? e : (e + end.size());
            if (partial) break;
            continue;
        }
        std::string name = llx_trim_copy(inner.substr(name_b, brace - name_b));

        // args object
        size_t args_i = brace;
        json args = llx_parse_functiongemma_object(inner, args_i, /*depth=*/0);

        common_chat_tool_call tc;
        tc.name = name;
        tc.arguments = args.dump();
        tc.id = "call_" + std::to_string(idx++);
        out.push_back(tc);

        pos = partial ? e : (e + end.size());
        if (partial) break;
    }
    return out;
}


