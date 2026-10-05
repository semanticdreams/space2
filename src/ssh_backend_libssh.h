#pragma once

#include "ssh_backend.h"

#include <memory>

namespace space::ssh
{

std::unique_ptr<Backend> make_libssh_backend();

}
