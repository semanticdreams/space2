#include <sol/sol.hpp>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#if defined(__unix__) || defined(__APPLE__)
#include <sys/stat.h>
#endif

#include "paths.h"

namespace fs = std::filesystem;

namespace {

constexpr std::uint64_t kMaxTextWindowBytes = 262144;
constexpr std::uint64_t kMaxByteRangeBytes = 262144;
constexpr std::uint64_t kAtomicCopyBufferBytes = 262144;
constexpr std::uint64_t kTokenFingerprintEdgeBytes = 65536;
constexpr char kUtf8Replacement[] = "\xEF\xBF\xBD";

std::string normalize_path(const fs::path& path)
{
    fs::path normalized = path.lexically_normal();
    return normalized.string();
}

std::string join_path_lua(sol::variadic_args args)
{
    if (args.size() == 0) {
        throw sol::error("fs.join_path requires at least one argument");
    }

    fs::path combined;
    bool first = true;
    for (const auto& arg : args) {
        if (!arg.is<std::string>()) {
            throw sol::error("fs.join_path expects string arguments");
        }
        const std::string part = arg.as<std::string>();
        if (first) {
            combined = fs::path(part);
            first = false;
        } else {
            combined /= part;
        }
    }

    return combined.string();
}

double file_time_to_seconds(const fs::file_time_type& tp)
{
    using namespace std::chrono;
    auto system_now = system_clock::now();
    auto file_now = fs::file_time_type::clock::now();
    auto adjusted = tp - file_now + system_now;
    auto time_point = time_point_cast<system_clock::duration>(adjusted);
    return duration<double>(time_point.time_since_epoch()).count();
}

std::string file_time_to_token_value(const fs::file_time_type& tp)
{
    return std::to_string(tp.time_since_epoch().count());
}

std::string stat_change_id(const fs::path& path)
{
#if defined(__APPLE__)
    struct stat metadata;
    if (::stat(path.c_str(), &metadata) != 0) {
        return std::string();
    }
    std::ostringstream out;
    out << metadata.st_dev << ':'
        << metadata.st_ino << ':'
        << metadata.st_size << ':'
        << metadata.st_mtimespec.tv_sec << ':'
        << metadata.st_mtimespec.tv_nsec << ':'
        << metadata.st_ctimespec.tv_sec << ':'
        << metadata.st_ctimespec.tv_nsec << ':'
        << metadata.st_mode << ':'
        << metadata.st_nlink;
    return out.str();
#elif defined(__unix__)
    struct stat metadata;
    if (::stat(path.c_str(), &metadata) != 0) {
        return std::string();
    }
    std::ostringstream out;
    out << metadata.st_dev << ':'
        << metadata.st_ino << ':'
        << metadata.st_size << ':'
        << metadata.st_mtim.tv_sec << ':'
        << metadata.st_mtim.tv_nsec << ':'
        << metadata.st_ctim.tv_sec << ':'
        << metadata.st_ctim.tv_nsec << ':'
        << metadata.st_mode << ':'
        << metadata.st_nlink;
    return out.str();
#else
    return std::string();
#endif
}

void hash_stream_bytes(std::uint64_t& hash, const char* data, std::streamsize size)
{
    for (std::streamsize index = 0; index < size; ++index) {
        hash ^= static_cast<unsigned char>(data[index]);
        hash *= 1099511628211ULL;
    }
}

std::string bounded_file_fingerprint(const fs::path& path, std::uint64_t size)
{
    if (size == 0) {
        return "empty";
    }

    std::ifstream input(path, std::ios::binary);
    if (!input) {
        return "unreadable";
    }

    std::vector<char> buffer(static_cast<std::size_t>(kTokenFingerprintEdgeBytes));
    std::uint64_t hash = 1469598103934665603ULL;
    std::uint64_t first_bytes = std::min<std::uint64_t>(size, kTokenFingerprintEdgeBytes);
    input.read(buffer.data(), static_cast<std::streamsize>(first_bytes));
    hash_stream_bytes(hash, buffer.data(), input.gcount());

    if (size > kTokenFingerprintEdgeBytes) {
        std::uint64_t last_bytes = std::min<std::uint64_t>(size, kTokenFingerprintEdgeBytes);
        input.clear();
        input.seekg(static_cast<std::streamoff>(size - last_bytes), std::ios::beg);
        input.read(buffer.data(), static_cast<std::streamsize>(last_bytes));
        hash_stream_bytes(hash, buffer.data(), input.gcount());
    }

    std::ostringstream out;
    out << size << ':' << hash;
    return out.str();
}

std::string permissions_to_string(fs::perms permissions)
{
    auto has = [permissions](fs::perms bit) {
        return (permissions & bit) != fs::perms::none;
    };

    std::string result = "---------";
    result[0] = has(fs::perms::owner_read) ? 'r' : '-';
    result[1] = has(fs::perms::owner_write) ? 'w' : '-';
    result[2] = has(fs::perms::owner_exec) ? 'x' : '-';
    result[3] = has(fs::perms::group_read) ? 'r' : '-';
    result[4] = has(fs::perms::group_write) ? 'w' : '-';
    result[5] = has(fs::perms::group_exec) ? 'x' : '-';
    result[6] = has(fs::perms::others_read) ? 'r' : '-';
    result[7] = has(fs::perms::others_write) ? 'w' : '-';
    result[8] = has(fs::perms::others_exec) ? 'x' : '-';
    return result;
}

bool is_hidden(const fs::path& path)
{
    std::string name = path.filename().string();
    return !name.empty() && name[0] == '.';
}

void throw_with_message(const std::string& prefix, const std::error_code& ec);

sol::table build_stat_table(sol::state_view lua, const fs::path& path)
{
    sol::table info = lua.create_table();
    info["path"] = normalize_path(path);
    info["name"] = path.filename().string();
    info["filename"] = info["name"];
    info["stem"] = path.stem().string();
    info["extension"] = path.has_extension() ? path.extension().string() : std::string();
    info["parent"] = path.parent_path().string();
    info["error"] = sol::lua_nil;

    std::error_code ec;
    fs::file_status status = fs::symlink_status(path, ec);
    if (ec) {
        info["exists"] = false;
        info["is-dir"] = false;
        info["is-file"] = false;
        info["is-symlink"] = false;
        info["is-other"] = false;
        info["permissions"] = std::string();
        info["size"] = sol::lua_nil;
        info["modified"] = sol::lua_nil;
        info["target"] = sol::lua_nil;
        info["type"] = "error";
        info["error"] = ec.message();
        return info;
    }

    bool exists = fs::exists(status);
    bool is_dir = fs::is_directory(status);
    bool is_file = fs::is_regular_file(status);
    bool is_symlink = fs::is_symlink(status);
    bool is_other = fs::is_other(status);

    info["exists"] = exists;
    info["is-dir"] = is_dir;
    info["is-file"] = is_file;
    info["is-symlink"] = is_symlink;
    info["is-other"] = is_other;
    info["permissions"] = permissions_to_string(status.permissions());

    std::string type = "other";
    if (!exists) {
        type = "missing";
    } else if (is_dir) {
        type = "directory";
    } else if (is_file) {
        type = "file";
    } else if (is_symlink) {
        type = "symlink";
    }
    info["type"] = type;

    if (exists && is_file) {
        std::error_code size_ec;
        auto size = fs::file_size(path, size_ec);
        if (!size_ec) {
            info["size"] = static_cast<uint64_t>(size);
        } else {
            info["size"] = sol::lua_nil;
        }
    } else {
        info["size"] = sol::lua_nil;
    }

    std::error_code time_ec;
    auto write_time = fs::last_write_time(path, time_ec);
    if (!time_ec) {
        info["modified"] = file_time_to_seconds(write_time);
    } else {
        info["modified"] = sol::lua_nil;
    }

    if (is_symlink) {
        std::error_code target_ec;
        fs::path target = fs::read_symlink(path, target_ec);
        if (!target_ec) {
            info["target"] = normalize_path(target);
        } else {
            info["target"] = sol::lua_nil;
        }
    } else {
        info["target"] = sol::lua_nil;
    }

    return info;
}

sol::table build_file_token_table(sol::state_view lua, const fs::path& input_path)
{
    if (input_path.empty()) {
        throw sol::error("fs.file_token: path must be non-empty");
    }

    std::error_code ec;
    fs::path absolute = fs::absolute(input_path, ec);
    throw_with_message("fs.file_token", ec);
    absolute = absolute.lexically_normal();

    fs::file_status status = fs::symlink_status(absolute, ec);
    throw_with_message("fs.file_token", ec);

    bool exists = fs::exists(status);
    bool is_file = fs::is_regular_file(status);
    std::uint64_t size = 0;
    std::string modified;

    if (exists && is_file) {
        auto file_size = fs::file_size(absolute, ec);
        throw_with_message("fs.file_token", ec);
        size = static_cast<std::uint64_t>(file_size);
    }

    if (exists) {
        auto write_time = fs::last_write_time(absolute, ec);
        throw_with_message("fs.file_token", ec);
        modified = file_time_to_token_value(write_time);
    }

    sol::table token = lua.create_table();
    std::string change_id = stat_change_id(absolute);
    if (exists && is_file) {
        change_id += ":sample:" + bounded_file_fingerprint(absolute, size);
    }
    token["path"] = absolute.string();
    token["exists"] = exists;
    token["is-file"] = is_file;
    token["size"] = size;
    token["modified"] = modified;
    token["change-id"] = change_id;
    token["permissions"] = permissions_to_string(status.permissions());
    return token;
}

void throw_with_message(const std::string& prefix, const std::error_code& ec)
{
    if (ec) {
        throw sol::error(prefix + ": " + ec.message());
    }
}

fs::perms permissions_from_string(const std::string& permissions)
{
    fs::perms result = fs::perms::none;
    if (permissions.size() >= 9) {
        if (permissions[0] == 'r') {
            result |= fs::perms::owner_read;
        }
        if (permissions[1] == 'w') {
            result |= fs::perms::owner_write;
        }
        if (permissions[2] == 'x') {
            result |= fs::perms::owner_exec;
        }
        if (permissions[3] == 'r') {
            result |= fs::perms::group_read;
        }
        if (permissions[4] == 'w') {
            result |= fs::perms::group_write;
        }
        if (permissions[5] == 'x') {
            result |= fs::perms::group_exec;
        }
        if (permissions[6] == 'r') {
            result |= fs::perms::others_read;
        }
        if (permissions[7] == 'w') {
            result |= fs::perms::others_write;
        }
        if (permissions[8] == 'x') {
            result |= fs::perms::others_exec;
        }
    }
    return result;
}

bool token_matches(sol::table current, sol::table expected)
{
    sol::object expected_path = expected["path"];
    sol::object expected_exists = expected["exists"];
    sol::object expected_is_file = expected["is-file"];
    sol::object expected_size = expected["size"];
    sol::object expected_modified = expected["modified"];
    sol::object expected_change_id = expected["change-id"];
    sol::object expected_permissions = expected["permissions"];

    return expected_path.is<std::string>()
        && expected_exists.is<bool>()
        && expected_is_file.is<bool>()
        && expected_size.is<std::uint64_t>()
        && expected_modified.is<std::string>()
        && expected_change_id.is<std::string>()
        && expected_permissions.is<std::string>()
        && current.get<std::string>("path") == expected_path.as<std::string>()
        && current.get<bool>("exists") == expected_exists.as<bool>()
        && current.get<bool>("is-file") == expected_is_file.as<bool>()
        && current.get<std::uint64_t>("size") == expected_size.as<std::uint64_t>()
        && current.get<std::string>("modified") == expected_modified.as<std::string>()
        && current.get<std::string>("change-id") == expected_change_id.as<std::string>()
        && current.get<std::string>("permissions") == expected_permissions.as<std::string>();
}

void write_source_segment(std::ofstream& output,
                          const std::string& source_path,
                          std::uint64_t offset,
                          std::uint64_t byte_count)
{
    std::error_code ec;
    std::uint64_t source_size = static_cast<std::uint64_t>(fs::file_size(source_path, ec));
    throw_with_message("fs.atomic_replace_if_current", ec);
    if (offset > source_size || byte_count > source_size - offset) {
        throw sol::error("fs.atomic_replace_if_current: source segment exceeds file size");
    }

    std::ifstream source(source_path, std::ios::binary);
    if (!source) {
        throw sol::error("fs.atomic_replace_if_current: unable to open source " + source_path);
    }
    source.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
    if (!source && byte_count > 0) {
        throw sol::error("fs.atomic_replace_if_current: unable to seek source " + source_path);
    }

    std::vector<char> buffer(static_cast<std::size_t>(kAtomicCopyBufferBytes));
    std::uint64_t remaining = byte_count;
    while (remaining > 0) {
        std::uint64_t chunk = std::min<std::uint64_t>(remaining, kAtomicCopyBufferBytes);
        source.read(buffer.data(), static_cast<std::streamsize>(chunk));
        std::streamsize read_count = source.gcount();
        if (read_count != static_cast<std::streamsize>(chunk)) {
            throw sol::error("fs.atomic_replace_if_current: unable to read source " + source_path);
        }
        output.write(buffer.data(), read_count);
        if (!output) {
            throw sol::error("fs.atomic_replace_if_current: unable to write replacement");
        }
        remaining -= static_cast<std::uint64_t>(read_count);
    }
}

void validate_replacement_segment(sol::table segment)
{
    sol::object text_object = segment["text"];
    sol::object source_path_object = segment["source-path"];
    bool has_text = text_object.valid() && text_object != sol::lua_nil;
    bool has_source_path = source_path_object.valid() && source_path_object != sol::lua_nil;

    if (has_text && has_source_path) {
        throw sol::error("fs.atomic_replace_if_current: segment must not mix text and source-path");
    }
    if (has_text) {
        if (!text_object.is<std::string>()) {
            throw sol::error("fs.atomic_replace_if_current: text segment must be a string");
        }
        return;
    }
    if (!has_source_path) {
        throw sol::error("fs.atomic_replace_if_current: segment requires text or source-path");
    }
    if (!source_path_object.is<std::string>()) {
        throw sol::error("fs.atomic_replace_if_current: source-path must be a string");
    }

    sol::object offset_object = segment["offset"];
    sol::object bytes_object = segment["bytes"];
    if (!offset_object.is<std::int64_t>() || !bytes_object.is<std::int64_t>()) {
        throw sol::error("fs.atomic_replace_if_current: source segment requires offset and bytes");
    }
    if (offset_object.as<std::int64_t>() < 0) {
        throw sol::error("fs.atomic_replace_if_current: offset must be non-negative");
    }
    if (bytes_object.as<std::int64_t>() < 0) {
        throw sol::error("fs.atomic_replace_if_current: bytes must be non-negative");
    }
}

std::size_t validate_replacement_segments(sol::table segments)
{
    std::size_t count = 0;
    std::size_t max_index = 0;

    for (const auto& entry : segments) {
        sol::object key = entry.first;
        sol::object value = entry.second;
        if (!key.is<std::int64_t>()) {
            throw sol::error("fs.atomic_replace_if_current: segments must be a contiguous array");
        }

        std::int64_t index = key.as<std::int64_t>();
        if (index <= 0) {
            throw sol::error("fs.atomic_replace_if_current: segments must be a contiguous array");
        }
        if (!value.is<sol::table>()) {
            throw sol::error("fs.atomic_replace_if_current: segment must be a table");
        }

        ++count;
        max_index = std::max(max_index, static_cast<std::size_t>(index));
        validate_replacement_segment(value.as<sol::table>());
    }

    if (count != max_index) {
        throw sol::error("fs.atomic_replace_if_current: segments must be a contiguous array");
    }

    return count;
}

void append_replacement_character(std::string& text)
{
    text.append(kUtf8Replacement, 3);
}

bool is_utf8_continuation(unsigned char byte)
{
    return byte >= 0x80 && byte <= 0xBF;
}

bool has_remaining_bytes(const std::string& raw, std::size_t offset, std::size_t count)
{
    return raw.size() - offset >= count;
}

bool valid_utf8_sequence(const std::string& raw, std::size_t offset, std::size_t length)
{
    const auto byte = [&raw, offset](std::size_t index) {
        return static_cast<unsigned char>(raw[offset + index]);
    };

    if (length == 2) {
        return byte(0) >= 0xC2 && byte(0) <= 0xDF && is_utf8_continuation(byte(1));
    }
    if (length == 3) {
        unsigned char first = byte(0);
        unsigned char second = byte(1);
        return ((first == 0xE0 && second >= 0xA0 && second <= 0xBF)
                || (first >= 0xE1 && first <= 0xEC && is_utf8_continuation(second))
                || (first == 0xED && second >= 0x80 && second <= 0x9F)
                || (first >= 0xEE && first <= 0xEF && is_utf8_continuation(second)))
            && is_utf8_continuation(byte(2));
    }
    if (length == 4) {
        unsigned char first = byte(0);
        unsigned char second = byte(1);
        return ((first == 0xF0 && second >= 0x90 && second <= 0xBF)
                || (first >= 0xF1 && first <= 0xF3 && is_utf8_continuation(second))
                || (first == 0xF4 && second >= 0x80 && second <= 0x8F))
            && is_utf8_continuation(byte(2))
            && is_utf8_continuation(byte(3));
    }
    return false;
}

bool valid_utf8_prefix(const std::string& raw, std::size_t offset, std::size_t length)
{
    std::size_t remaining = raw.size() - offset;
    if (remaining >= length || remaining == 0) {
        return false;
    }

    unsigned char first = static_cast<unsigned char>(raw[offset]);
    if (remaining == 1) {
        return true;
    }

    unsigned char second = static_cast<unsigned char>(raw[offset + 1]);
    if (length == 2) {
        return is_utf8_continuation(second);
    }
    if (length == 3) {
        return (first == 0xE0 && second >= 0xA0 && second <= 0xBF)
            || (first >= 0xE1 && first <= 0xEC && is_utf8_continuation(second))
            || (first == 0xED && second >= 0x80 && second <= 0x9F)
            || (first >= 0xEE && first <= 0xEF && is_utf8_continuation(second));
    }
    if (length == 4) {
        bool valid_second = (first == 0xF0 && second >= 0x90 && second <= 0xBF)
            || (first >= 0xF1 && first <= 0xF3 && is_utf8_continuation(second))
            || (first == 0xF4 && second >= 0x80 && second <= 0x8F);
        if (!valid_second) {
            return false;
        }
        if (remaining == 2) {
            return true;
        }
        return is_utf8_continuation(static_cast<unsigned char>(raw[offset + 2]));
    }
    return false;
}

std::size_t utf8_sequence_length(unsigned char first)
{
    if (first >= 0xC2 && first <= 0xDF) {
        return 2;
    }
    if (first >= 0xE0 && first <= 0xEF) {
        return 3;
    }
    if (first >= 0xF0 && first <= 0xF4) {
        return 4;
    }
    return 0;
}

std::pair<std::string, bool> sanitize_text_window(const std::string& raw)
{
    std::string text;
    text.reserve(raw.size());
    bool truncated_utf8 = false;

    for (std::size_t i = 0; i < raw.size();) {
        unsigned char first = static_cast<unsigned char>(raw[i]);
        if (first == 0) {
            append_replacement_character(text);
            ++i;
        } else if (first <= 0x7F) {
            text.push_back(static_cast<char>(first));
            ++i;
        } else {
            std::size_t sequence_length = utf8_sequence_length(first);
            if (sequence_length == 0) {
                append_replacement_character(text);
                ++i;
            } else if (!has_remaining_bytes(raw, i, sequence_length)) {
                if (valid_utf8_prefix(raw, i, sequence_length)) {
                    append_replacement_character(text);
                    truncated_utf8 = true;
                    break;
                }
                append_replacement_character(text);
                ++i;
            } else if (valid_utf8_sequence(raw, i, sequence_length)) {
                text.append(raw, i, sequence_length);
                i += sequence_length;
            } else {
                append_replacement_character(text);
                ++i;
            }
        }
    }

    return {text, truncated_utf8};
}

} // namespace

std::string fs_cwd()
{
    std::error_code ec;
    fs::path cwd = fs::current_path(ec);
    throw_with_message("fs.cwd", ec);
    return normalize_path(cwd);
}

void fs_set_cwd(const std::string& path)
{
    std::error_code ec;
    fs::current_path(path, ec);
    throw_with_message("fs.set_cwd", ec);
}

std::string fs_absolute(const std::string& path)
{
    std::error_code ec;
    fs::path absolute = fs::absolute(path, ec);
    throw_with_message("fs.absolute", ec);
    return normalize_path(absolute);
}

std::string fs_relative(const std::string& path, sol::optional<std::string> base_opt)
{
    fs::path base_path;
    std::error_code ec;
    if (base_opt) {
        base_path = fs::path(base_opt.value());
    } else {
        base_path = fs::current_path(ec);
        throw_with_message("fs.relative", ec);
    }

    fs::path relative = fs::relative(path, base_path, ec);
    throw_with_message("fs.relative", ec);
    return normalize_path(relative);
}

std::string fs_parent(const std::string& path)
{
    fs::path parent = fs::path(path).parent_path();
    return parent.string();
}

bool fs_exists(const std::string& path)
{
    std::error_code ec;
    bool exists = fs::exists(path, ec);
    throw_with_message("fs.exists", ec);
    return exists;
}

sol::table fs_stat(sol::this_state ts, const std::string& path)
{
    sol::state_view lua(ts);
    return build_stat_table(lua, fs::path(path));
}

sol::table fs_file_token(sol::this_state ts, const std::string& path)
{
    sol::state_view lua(ts);
    return build_file_token_table(lua, fs::path(path));
}

sol::table fs_list_dir(sol::this_state ts, const std::string& path, sol::optional<bool> include_hidden_opt,
                       sol::optional<bool> strict_opt)
{
    sol::state_view lua(ts);
    sol::table items = lua.create_table();

    bool include_hidden = include_hidden_opt.value_or(true);

    std::error_code ec;
    fs::directory_options options = strict_opt.value_or(false)
        ? fs::directory_options::none : fs::directory_options::skip_permission_denied;
    fs::directory_iterator it(path.empty() ? fs::path(".") : fs::path(path), options, ec);
    throw_with_message("fs.list_dir", ec);

    size_t index = 1;
    fs::directory_iterator end;
    while (it != end) {
        const fs::path& entry_path = it->path();
        if (!include_hidden && is_hidden(entry_path)) {
            std::error_code step_ec;
            it.increment(step_ec);
            throw_with_message("fs.list_dir", step_ec);
            continue;
        }
        sol::table entry = build_stat_table(lua, entry_path);
        items[index++] = entry;

        std::error_code step_ec;
        it.increment(step_ec);
        throw_with_message("fs.list_dir", step_ec);
    }

    return items;
}

std::string fs_read_file(const std::string& path)
{
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        throw sol::error("fs.read_file: unable to open " + path);
    }
    std::string contents;
    char buffer[8192];
    while (file.read(buffer, sizeof(buffer)) || file.gcount() > 0) {
        contents.append(buffer, static_cast<std::size_t>(file.gcount()));
    }
    if (file.bad() || !file.eof()) {
        throw sol::error("fs.read_file: unable to read " + path);
    }
    return contents;
}

sol::table fs_read_text_window(sol::this_state ts,
                               const std::string& path,
                               std::int64_t offset,
                               std::int64_t max_bytes)
{
    if (path.empty()) {
        throw sol::error("fs.read_text_window: path must be non-empty");
    }
    if (offset < 0) {
        throw sol::error("fs.read_text_window: offset must be non-negative");
    }
    if (max_bytes <= 0) {
        throw sol::error("fs.read_text_window: max-bytes must be positive");
    }

    std::error_code size_ec;
    std::uint64_t size = static_cast<std::uint64_t>(fs::file_size(path, size_ec));
    throw_with_message("fs.read_text_window", size_ec);

    std::uint64_t requested = static_cast<std::uint64_t>(max_bytes);
    std::uint64_t capped = std::min(requested, kMaxTextWindowBytes);
    std::uint64_t start = static_cast<std::uint64_t>(offset);
    std::uint64_t available = start < size ? size - start : 0;
    std::uint64_t bytes_to_read = std::min(capped, available);

    std::ifstream file(path, std::ios::binary);
    if (!file) {
        throw sol::error("fs.read_text_window: unable to open " + path);
    }

    file.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
    if (!file && bytes_to_read > 0) {
        throw sol::error("fs.read_text_window: unable to seek " + path);
    }

    std::string raw;
    raw.resize(static_cast<std::size_t>(bytes_to_read));
    if (bytes_to_read > 0) {
        file.read(raw.data(), static_cast<std::streamsize>(bytes_to_read));
        raw.resize(static_cast<std::size_t>(file.gcount()));
        if (!file.eof() && file.fail()) {
            throw sol::error("fs.read_text_window: unable to read " + path);
        }
    }

    auto [text, truncated_utf8] = sanitize_text_window(raw);
    std::uint64_t bytes_read = static_cast<std::uint64_t>(raw.size());
    std::uint64_t next_offset = start + bytes_read;

    sol::state_view lua(ts);
    sol::table result = lua.create_table();
    result["path"] = path;
    result["offset"] = start;
    result["next-offset"] = next_offset;
    result["size"] = size;
    result["bytes-read"] = bytes_read;
    result["eof"] = next_offset >= size;
    result["text"] = text;
    result["truncated-utf8"] = truncated_utf8;
    return result;
}

sol::table fs_read_byte_range(sol::this_state ts,
                              const std::string& path,
                              std::int64_t offset,
                              std::int64_t max_bytes)
{
    if (path.empty()) {
        throw sol::error("fs.read_byte_range: path must be non-empty");
    }
    if (offset < 0) {
        throw sol::error("fs.read_byte_range: offset must be non-negative");
    }
    if (max_bytes <= 0) {
        throw sol::error("fs.read_byte_range: max-bytes must be positive");
    }

    std::error_code size_ec;
    std::uint64_t size = static_cast<std::uint64_t>(fs::file_size(path, size_ec));
    throw_with_message("fs.read_byte_range", size_ec);

    std::uint64_t requested = static_cast<std::uint64_t>(max_bytes);
    std::uint64_t capped = std::min(requested, kMaxByteRangeBytes);
    std::uint64_t start = static_cast<std::uint64_t>(offset);
    std::uint64_t available = start < size ? size - start : 0;
    std::uint64_t bytes_to_read = std::min(capped, available);

    std::ifstream file(path, std::ios::binary);
    if (!file) {
        throw sol::error("fs.read_byte_range: unable to open " + path);
    }
    file.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
    if (!file && bytes_to_read > 0) {
        throw sol::error("fs.read_byte_range: unable to seek " + path);
    }

    std::string bytes;
    bytes.resize(static_cast<std::size_t>(bytes_to_read));
    if (bytes_to_read > 0) {
        file.read(bytes.data(), static_cast<std::streamsize>(bytes_to_read));
        bytes.resize(static_cast<std::size_t>(file.gcount()));
        if (!file.eof() && file.fail()) {
            throw sol::error("fs.read_byte_range: unable to read " + path);
        }
    }

    std::uint64_t bytes_read = static_cast<std::uint64_t>(bytes.size());
    std::uint64_t next_offset = start + bytes_read;

    sol::state_view lua(ts);
    sol::table result = lua.create_table();
    result["path"] = fs_absolute(path);
    result["offset"] = start;
    result["next-offset"] = next_offset;
    result["size"] = size;
    result["bytes-read"] = bytes_read;
    result["eof"] = next_offset >= size;
    result["bytes"] = bytes;
    return result;
}

void fs_write_file(const std::string& path, const std::string& contents)
{
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    if (!file) {
        throw sol::error("fs.write_file: unable to write " + path);
    }
    file << contents;
    file.flush();
    if (!file) {
        throw sol::error("fs.write_file: unable to flush " + path);
    }
    file.close();
    if (!file) {
        throw sol::error("fs.write_file: unable to close " + path);
    }
}

void fs_append_file(const std::string& path, const std::string& contents)
{
    std::ofstream file(path, std::ios::binary | std::ios::app);
    if (!file) {
        throw sol::error("fs.append_file: unable to append " + path);
    }
    file << contents;
}

sol::table fs_atomic_replace_if_current(sol::this_state ts,
                                        const std::string& path,
                                        sol::table segments,
                                        sol::table expected_token,
                                        sol::optional<sol::table> opts)
{
    if (path.empty()) {
        throw sol::error("fs.atomic_replace_if_current: path must be non-empty");
    }

    sol::state_view lua(ts);
    sol::table current_token = build_file_token_table(lua, fs::path(path));
    if (!token_matches(current_token, expected_token)) {
        throw sol::error("fs.atomic_replace_if_current: file changed since token");
    }
    std::size_t segment_count = validate_replacement_segments(segments);

    fs::path absolute_path = fs::path(current_token.get<std::string>("path"));
    fs::path parent = absolute_path.parent_path();
    auto now = std::chrono::steady_clock::now().time_since_epoch().count();
    fs::path temp_path = parent / (absolute_path.filename().string() + ".space-tmp-" + std::to_string(now));
    fs::perms original_permissions = permissions_from_string(current_token.get<std::string>("permissions"));
    sol::optional<sol::function> test_before_final_validate;
    if (opts) {
        sol::object hook_object = (*opts)["test-before-final-validate"];
        if (hook_object.valid() && hook_object != sol::lua_nil) {
            if (!hook_object.is<sol::function>()) {
                throw sol::error("fs.atomic_replace_if_current: test-before-final-validate must be a function");
            }
            test_before_final_validate = hook_object.as<sol::function>();
        }
    }

    try {
        std::ofstream output(temp_path, std::ios::binary | std::ios::trunc);
        if (!output) {
            throw sol::error("fs.atomic_replace_if_current: unable to create temporary file");
        }

        for (std::size_t index = 1; index <= segment_count; ++index) {
            sol::object segment_object = segments[index];
            sol::table segment = segment_object.as<sol::table>();
            sol::object text_object = segment["text"];
            sol::object source_path_object = segment["source-path"];
            bool has_text = text_object.valid() && text_object != sol::lua_nil;
            bool has_source_path = source_path_object.valid() && source_path_object != sol::lua_nil;

            if (has_text && has_source_path) {
                throw sol::error("fs.atomic_replace_if_current: segment must not mix text and source-path");
            }
            if (has_text) {
                if (!text_object.is<std::string>()) {
                    throw sol::error("fs.atomic_replace_if_current: text segment must be a string");
                }
                std::string text = text_object.as<std::string>();
                output.write(text.data(), static_cast<std::streamsize>(text.size()));
                if (!output) {
                    throw sol::error("fs.atomic_replace_if_current: unable to write replacement");
                }
                continue;
            }
            if (!has_source_path) {
                throw sol::error("fs.atomic_replace_if_current: segment requires text or source-path");
            }
            if (!source_path_object.is<std::string>()) {
                throw sol::error("fs.atomic_replace_if_current: source-path must be a string");
            }

            sol::object offset_object = segment["offset"];
            sol::object bytes_object = segment["bytes"];
            if (!offset_object.is<std::int64_t>() || !bytes_object.is<std::int64_t>()) {
                throw sol::error("fs.atomic_replace_if_current: source segment requires offset and bytes");
            }
            std::int64_t offset = offset_object.as<std::int64_t>();
            std::int64_t byte_count = bytes_object.as<std::int64_t>();
            if (offset < 0) {
                throw sol::error("fs.atomic_replace_if_current: offset must be non-negative");
            }
            if (byte_count < 0) {
                throw sol::error("fs.atomic_replace_if_current: bytes must be non-negative");
            }
            write_source_segment(output,
                                 source_path_object.as<std::string>(),
                                 static_cast<std::uint64_t>(offset),
                                 static_cast<std::uint64_t>(byte_count));
        }

        output.close();
        if (!output) {
            throw sol::error("fs.atomic_replace_if_current: unable to finalize replacement");
        }

        std::error_code ec;
        fs::permissions(temp_path, original_permissions, fs::perm_options::replace, ec);
        throw_with_message("fs.atomic_replace_if_current", ec);

        if (test_before_final_validate) {
            sol::protected_function hook = test_before_final_validate.value();
            sol::protected_function_result hook_result = hook();
            if (!hook_result.valid()) {
                sol::error err = hook_result;
                throw err;
            }
        }

        current_token = build_file_token_table(lua, absolute_path);
        if (!token_matches(current_token, expected_token)) {
            throw sol::error("fs.atomic_replace_if_current: file changed since token");
        }

        fs::rename(temp_path, absolute_path, ec);
        throw_with_message("fs.atomic_replace_if_current", ec);
    } catch (...) {
        std::error_code cleanup_ec;
        fs::remove(temp_path, cleanup_ec);
        throw;
    }

    sol::table result = lua.create_table();
    result["saved"] = true;
    result["path"] = current_token.get<std::string>("path");
    result["token"] = build_file_token_table(lua, absolute_path);
    return result;
}

bool fs_create_dir(const std::string& path)
{
    std::error_code ec;
    bool created = fs::create_directory(path, ec);
    throw_with_message("fs.create_dir", ec);
    return created;
}

bool fs_create_dirs(const std::string& path)
{
    std::error_code ec;
    bool created = fs::create_directories(path, ec);
    throw_with_message("fs.create_dirs", ec);
    return created;
}

bool fs_remove(const std::string& path)
{
    std::error_code ec;
    bool removed = fs::remove(path, ec);
    throw_with_message("fs.remove", ec);
    return removed;
}

uintmax_t fs_remove_all(const std::string& path)
{
    std::error_code ec;
    uintmax_t total = 0;
    auto count = fs::remove_all(path, ec);
    if (count != static_cast<uintmax_t>(-1)) {
        total += count;
    }
    for (int retry = 0; ec && retry < 10; ++retry) {
#ifdef _WIN32
        if (!(ec.category() == std::system_category()
              && (ec.value() == 32   // ERROR_SHARING_VIOLATION
                  || ec.value() == 33))) // ERROR_LOCK_VIOLATION
            break;
#else
        if (!(ec == std::errc::device_or_resource_busy   // EBUSY
              || ec == std::errc::resource_unavailable_try_again)) // EAGAIN
            break;
#endif
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        ec.clear();
        count = fs::remove_all(path, ec);
        if (count != static_cast<uintmax_t>(-1)) {
            total += count;
        }
    }
    throw_with_message("fs.remove_all", ec);
    return total;
}

void fs_rename(const std::string& from, const std::string& to)
{
    std::error_code ec;
    fs::rename(from, to, ec);
    throw_with_message("fs.rename", ec);
}

void fs_copy_file(const std::string& from, const std::string& to, bool overwrite)
{
    std::error_code ec;
    auto options = overwrite ? fs::copy_options::overwrite_existing : fs::copy_options::none;
    fs::copy_file(from, to, options, ec);
    throw_with_message("fs.copy_file", ec);
}

void fs_copy(const std::string& from, const std::string& to, bool recursive, bool overwrite)
{
    std::error_code ec;
    fs::copy_options options = fs::copy_options::copy_symlinks;
    if (recursive) {
        options |= fs::copy_options::recursive;
    }
    if (overwrite) {
        options |= fs::copy_options::overwrite_existing;
    }
    fs::copy(from, to, options, ec);
    throw_with_message("fs.copy", ec);
}

void fs_touch(const std::string& path)
{
    std::error_code ec;
    bool exists = fs::exists(path, ec);
    throw_with_message("fs.touch", ec);

    if (!exists) {
        std::ofstream file(path, std::ios::binary | std::ios::app);
        if (!file) {
            throw sol::error("fs.touch: unable to create " + path);
        }
        return;
    }

    auto now = fs::file_time_type::clock::now();
    fs::last_write_time(path, now, ec);
    throw_with_message("fs.touch", ec);
}

sol::table fs_space(sol::this_state ts, sol::optional<std::string> path_opt)
{
    sol::state_view lua(ts);
    std::error_code ec;
    fs::path target_path;

    if (path_opt && !path_opt->empty()) {
        target_path = fs::path(path_opt.value());
    } else {
        target_path = fs::current_path(ec);
        throw_with_message("fs.space", ec);
    }

    fs::space_info info = fs::space(target_path, ec);
    throw_with_message("fs.space", ec);

    sol::table result = lua.create_table();
    result["capacity"] = static_cast<uint64_t>(info.capacity);
    result["free"] = static_cast<uint64_t>(info.free);
    result["available"] = static_cast<uint64_t>(info.available);
    return result;
}

namespace {

sol::table create_fs_table(sol::state_view lua)
{
    sol::table fs_table = lua.create_table();
    fs_table.set_function("cwd", &fs_cwd);
    fs_table.set_function("set-cwd", &fs_set_cwd);
    fs_table.set_function("absolute", &fs_absolute);
    fs_table.set_function("relative", &fs_relative);
    fs_table.set_function("parent", &fs_parent);
    fs_table.set_function("join-path", &join_path_lua);
    fs_table.set_function("exists", &fs_exists);
    fs_table.set_function("stat", &fs_stat);
    fs_table.set_function("file-token", &fs_file_token);
    fs_table.set_function("list-dir", &fs_list_dir);
    fs_table.set_function("read-file", &fs_read_file);
    fs_table.set_function("read-text-window", &fs_read_text_window);
    fs_table.set_function("read-byte-range", &fs_read_byte_range);
    fs_table.set_function("write-file", &fs_write_file);
    fs_table.set_function("append-file", &fs_append_file);
    fs_table.set_function("atomic-replace-if-current", &fs_atomic_replace_if_current);
    fs_table.set_function("create-dir", &fs_create_dir);
    fs_table.set_function("create-dirs", &fs_create_dirs);
    fs_table.set_function("remove", &fs_remove);
    fs_table.set_function("remove-all", &fs_remove_all);
    fs_table.set_function("rename", &fs_rename);
    fs_table.set_function("copy-file", [](const std::string& from, const std::string& to, sol::optional<bool> overwrite) {
        fs_copy_file(from, to, overwrite.value_or(false));
    });
    fs_table.set_function("copy", [](const std::string& from, const std::string& to, sol::optional<bool> recursive, sol::optional<bool> overwrite) {
        fs_copy(from, to, recursive.value_or(true), overwrite.value_or(false));
    });
    fs_table.set_function("touch", &fs_touch);
    fs_table.set_function("space", &fs_space);
    return fs_table;
}

} // namespace

void lua_bind_fs(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("fs", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_fs_table(lua);
    });
}
