#include "error_reporting.h"
#include "httplib.h"

#include <chrono>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

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
    server.Post(R"(.*)", [&](const httplib::Request& req, httplib::Response& res) {
        std::lock_guard<std::mutex> lock(mutex);
        if (req.body.find("bugsink.narlun.com") != std::string::npos) {
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
    options.database_path = (std::filesystem::temp_directory_path()
                             / ("space-error-reporting-wrapper-test-" + std::to_string(port)))
                                .string();
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
    return check(ok, error_message)
            && check(local_only_delivery, "no request body referenced bugsink.narlun.com")
            && check(wait_for_body_containing(bodies, mutex, "space local test exception"), "local event received")
        ? 0
        : 1;
}
