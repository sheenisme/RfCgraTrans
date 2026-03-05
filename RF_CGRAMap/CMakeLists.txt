cmake_minimum_required(VERSION 3.10)
project(RfCgraMap)

#Generate the static library from the library sources
add_library(RfCgraMap STATIC
        src/CGRA.cpp  
        src/Register.cpp  
        src/DFG.cpp 
        src/tool.cpp 
        src/GraphRegister.cpp  
        src/Path.cpp
        )

target_include_directories(RfCgraMap
        PUBLIC
        ${PROJECT_SOURCE_DIR}/include
        )

set(rfCGRAH include/CGRA.h  
        include/Register.h  
        include/DFG.h 
        include/tool.h 
        include/GraphRegister.h  
        include/Path.h)

# Use the CMAKE_INSTALL_PREFIX variable to specify the installation directory. If it is not set, default to the project source directory.
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX ${PROJECT_SOURCE_DIR} CACHE PATH "Installation directory" FORCE)
endif()

# Install the library and header files
install(TARGETS RfCgraMap
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        )
install(DIRECTORY include/
        DESTINATION include
        FILES_MATCHING PATTERN "*.h"
        )