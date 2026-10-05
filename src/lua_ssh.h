#pragma once

#include "ssh_service.h"

#include <memory>

#include <sol/sol.hpp>

void lua_bind_ssh(sol::state& lua, std::shared_ptr<space::ssh::Service> service);
void lua_ssh_dispatch(sol::state& lua);
void lua_ssh_drop(sol::state& lua);
