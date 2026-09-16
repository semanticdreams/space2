#include "error_reporting.h"
#include "httplib.h"

#include <chrono>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

std::string unique_database_path(const std::string& name)
{
    const auto path = std::filesystem::temp_directory_path()
        / (name + "-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    std::filesystem::remove_all(path);
    return path.string();
}

bool check_elapsed_under(std::chrono::steady_clock::duration elapsed,
                         std::chrono::milliseconds limit,
                         const std::string& message)
{
    if (elapsed < limit) {
        return true;
    }
    std::cerr << "FAIL: " << message << " elapsed_ms="
              << std::chrono::duration_cast<std::chrono::milliseconds>(elapsed).count()
              << " limit_ms=" << limit.count() << "\n";
    return false;
}

} // namespace

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

bool wait_for_body_containing(const std::vector<std::string>& bodies,
                              std::mutex& mutex,
                              const std::string& needle)
{
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (std::chrono::steady_clock::now() < deadline) {
        {
            std::lock_guard<std::mutex> lock(mutex);
            for (const std::string& body : bodies) {
                if (body.find(needle) != std::string::npos) {
                    return true;
                }
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    return false;
}

int main()
{
    if (!check(!error_reporting::capture_message(error_reporting::Level::Info, "test", "disabled"),
               "capture before init returns false")) {
        return 1;
    }
    error_reporting::InitOptions invalid_options;
    invalid_options.dsn = "not-a-sentry-dsn";
    std::string invalid_error;
    if (!check(!error_reporting::init(invalid_options, &invalid_error), "invalid DSN is rejected")) {
        return 1;
    }

    httplib::Server server;
    std::mutex mutex;
    std::vector<std::string> bodies;
    bool forbidden_host_seen = false;
    const std::string forbidden_host = std::string("bugsink.") + "narlun.com";
    server.Post(R"(.*)", [&](const httplib::Request& req, httplib::Response& res) {
        std::lock_guard<std::mutex> lock(mutex);
        if (req.body.find(forbidden_host) != std::string::npos) {
            forbidden_host_seen = true;
            res.status = 500;
            return;
        }
        bodies.push_back(req.body);
        res.status = 200;
        res.set_content("{}", "application/json");
    });
    int port = server.bind_to_any_port("127.0.0.1");
    if (!check(port > 0, "bind local server")) {
        return 1;
    }
    std::thread thread([&]() { server.listen_after_bind(); });

    error_reporting::InitOptions options;
    options.dsn = "http://public@127.0.0.1:" + std::to_string(port) + "/1";
    options.database_path = unique_database_path("space-error-reporting-wrapper-test");
    std::string error_message;
    bool ok = error_reporting::init(options, &error_message);
    ok = ok && error_reporting::capture_exception(
                   "TestException", "space local test exception", "stack line", {{"test", "error-reporting"}});
    error_reporting::flush(5000);
    error_reporting::shutdown();
    server.stop();
    thread.join();
    bool local_only_delivery = false;
    {
        std::lock_guard<std::mutex> lock(mutex);
        local_only_delivery = !forbidden_host_seen;
    }
    if (!check(ok, error_message)
        || !check(local_only_delivery, "no request body referenced production Bugsink host")
        || !check(wait_for_body_containing(bodies, mutex, "space local test exception"), "local event received")) {
        return 1;
    }

    httplib::Server slow_server;
    slow_server.Post(R"(.*)", [](const httplib::Request&, httplib::Response& res) {
        std::this_thread::sleep_for(std::chrono::milliseconds(3000));
        res.status = 200;
        res.set_content("{}", "application/json");
    });
    int slow_port = slow_server.bind_to_any_port("127.0.0.1");
    if (!check(slow_port > 0, "bind slow local server")) {
        return 1;
    }
    std::thread slow_thread([&]() { slow_server.listen_after_bind(); });

    error_reporting::InitOptions slow_options;
    slow_options.dsn = "http://public@127.0.0.1:" + std::to_string(slow_port) + "/1";
    slow_options.database_path = unique_database_path("space-error-reporting-slow-wrapper-test");
    std::string slow_error_message;
    const auto slow_start = std::chrono::steady_clock::now();
    bool slow_ok = error_reporting::init(slow_options, &slow_error_message);
    slow_ok = slow_ok && error_reporting::capture_message(error_reporting::Level::Error, "test", "slow server message");
    error_reporting::shutdown();
    const auto slow_elapsed = std::chrono::steady_clock::now() - slow_start;
    slow_server.stop();
    slow_thread.join();
    if (!check(slow_ok, slow_error_message)
        || !check_elapsed_under(slow_elapsed, std::chrono::milliseconds(1000),
                                "capture and shutdown against slow server should be bounded")) {
        return 1;
    }

    error_reporting::InitOptions unavailable_options;
    unavailable_options.dsn = "http://public@127.0.0.1:9/1";
    unavailable_options.database_path = unique_database_path("space-error-reporting-unavailable-wrapper-test");
    std::string unavailable_error_message;
    const auto unavailable_start = std::chrono::steady_clock::now();
    bool unavailable_ok = error_reporting::init(unavailable_options, &unavailable_error_message);
    unavailable_ok = unavailable_ok
        && error_reporting::capture_message(error_reporting::Level::Error, "test", "unavailable server message");
    error_reporting::shutdown();
    const auto unavailable_elapsed = std::chrono::steady_clock::now() - unavailable_start;
    if (!check(unavailable_ok, unavailable_error_message)
        || !check_elapsed_under(unavailable_elapsed, std::chrono::milliseconds(1000),
                                "capture and shutdown against unavailable server should be bounded")) {
        return 1;
    }

    return 0;
}
