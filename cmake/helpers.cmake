#
# Copyright 2018, Data61
# Commonwealth Scientific and Industrial Research Organisation (CSIRO)
# ABN 41 687 119 230.
#
# This software may be distributed and modified according to the terms of
# the BSD 2-Clause license. Note that NO WARRANTY is provided.
# See "LICENSE_BSD2.txt" for details.
#
# @TAG(DATA61_BSD)
#

# Helper that takes a filename and makes the directory where that file would go if
function(EnsureDir filename)
    get_filename_component(dir "${filename}" DIRECTORY)
    file(MAKE_DIRECTORY "${dir}")
endfunction(EnsureDir)

# Wrapper around `file(RENAME` that ensures the rename succeeds by creating the destination
# directory if it does not exist
function(Rename src dest)
    EnsureDir("${dest}")
    file(RENAME "${src}" "${dest}")
endfunction(Rename)

# Wrapper around using `cmake -E copy` that tries to ensure the copy succeeds by first
# creating the destination directory if it does not exist
function(Copy src dest)
    EnsureDir("${dest}")
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E copy "${src}" "${dest}"
        RESULT_VARIABLE exit_status
    )
    if (NOT ("${exit_status}" EQUAL 0))
        message(FATAL_ERROR "Failed to copy ${src} to ${dest}")
    endif()
endfunction(Copy)

# Return non-zero if files one and two are not the same.
function(DiffFiles res one two)
        execute_process(
            COMMAND diff -q "${one}" "${two}"
            RESULT_VARIABLE exit_status
            OUTPUT_VARIABLE OUTPUT
            ERROR_VARIABLE OUTPUT
        )
        set(${res} ${exit_status} PARENT_SCOPE)
endfunction()

# Try to update output and old with the value of input
# Only update output with input if input != old
# Fail if input != old and output != old
function(CopyIfUpdated input output old)
    if (EXISTS ${output})
        DiffFiles(template_updated ${input} ${old})
        DiffFiles(instance_updated ${output} ${old})
        if(template_updated AND instance_updated)
            message(FATAL_ERROR "Template has been updated and the instantiated tutorial has been updated. \
             Changes would be lost if proceeded.")
        endif()
        set(do_update ${template_updated})
    else()
        set(do_update TRUE)
    endif()
    if(do_update)
        Copy(${input} ${output})
        Copy(${input} ${old})
    endif()
    file(REMOVE ${input})

endfunction()


# Copies a tutorial source file into the destination location.
# `parent_dest` is the name of a variable where the full path of the outputted file will be placed
# `name` is the filename relative to the current source directory but without any '.template' or '.source' extension
#   This name then becomes the name that the user of the tutorial will see and edit
# `extension` is any extension on the `name` to provide the full file path. By convention templated files
#   '.template' and non-templated files have '.source'. The reason for always having an extension is to
#   prevent them being accidentally used from the source directory instead of destination version that the
#   user will be editing
# `is_template` indicates whether the file should be put through the template preprocessor or not
function(CopyTutorialSource parent_dest name extension is_template)
    if (BUILD_SOLUTIONS)
        set(args "--solution")
    endif()
    set(dest_folder "${TUTORIAL_DIR}")
    set(temp_folder "temp/${dest_folder}")
    set(template "${CMAKE_CURRENT_SOURCE_DIR}/${name}${extension}")
    set(dest "${CMAKE_SOURCE_DIR}/${dest_folder}/${name}")
    set(temp "${CMAKE_BINARY_DIR}/${temp_folder}/${name}.temp")
    set(orig "${CMAKE_BINARY_DIR}/${temp_folder}/${name}.orig")
    set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${template}")
    # Generate the temp file. We do this unconditionally as it should be cheap and our only
    # dependency on the TemplateTool is by requesting that this whole script re-runs
    if (is_template)
        EnsureDir("${temp}")
        execute_process(
            COMMAND "${TemplateTool}" ${args}
            RESULT_VARIABLE exit_status
            INPUT_FILE "${template}"
            OUTPUT_FILE "${temp}"
            ERROR_VARIABLE error_message
        )
        if (NOT ("${exit_status}" EQUAL 0))
            message(FATAL_ERROR "Template parsing of ${template} failed with code ${exit_status} and stderr: \"${error_message}\"")
        endif()
    else()
        Copy("${template}" "${temp}")
    endif()
    CopyIfUpdated(${temp} ${dest} ${orig})
    # Determine the relative portion of the destination from what we believe the
    # users working directory (CMAKE_BINARY_DIR) to be
    file(RELATIVE_PATH rel "${CMAKE_BINARY_DIR}" "${dest}")
    if(is_template)
        set_property(GLOBAL APPEND PROPERTY template_files "${rel}")
    else()
        set_property(GLOBAL APPEND PROPERTY companion_files "${rel}")
    endif()
    set(${parent_dest} "${dest}" PARENT_SCOPE)
endfunction(CopyTutorialSource)

# Wrapper around `add_executable` that understands two additional list arguments in the form of
# TEMPLATE_SOURCES and TUTORIAL_SOURCES. These are passed through CopyTutorialSource and the resulting
# files are given to `add_executable` along with any other additional unparsed arguments
function(add_tutorials_executable name)
    cmake_parse_arguments(PARSE_ARGV 1 ADD_TUT_EXE "" "" "TEMPLATE_SOURCES;TUTORIAL_SOURCES")
    foreach(source IN LISTS ADD_TUT_EXE_TUTORIAL_SOURCES)
        CopyTutorialSource(dest "${source}" "" FALSE)
        list(APPEND sources "${dest}")
    endforeach()
    foreach(source IN LISTS ADD_TUT_EXE_TEMPLATE_SOURCES)
        CopyTutorialSource(dest "${source}" "" TRUE)
        list(APPEND sources "${dest}")
    endforeach()
    add_executable(${name} ${ADD_TUT_EXE_UNPARSED_ARGUMENTS} ${sources})
endfunction(add_tutorials_executable)

# Wrapper around `DeclareCAmkESComponent` that understands two additional list arguments in the form of
# TEMPLATE_SOURCES and TUTORIAL_SOURCES. These are passed through CopyTutorialSource and the resulting
# files are given to `DeclareCAmkESComponent` along with any other additional unparsed arguments
function(DeclareTutorialsCAmkESComponent name)
    cmake_parse_arguments(PARSE_ARGV 1 ADD_TUT_COMPONENT "" "" "TUTORIAL_SOURCES;TEMPLATE_SOURCES")
    foreach(source IN LISTS ADD_TUT_COMPONENT_TUTORIAL_SOURCES)
        CopyTutorialSource(dest "${source}" "" FALSE)
        list(APPEND sources "${dest}")
    endforeach()
    foreach(source IN LISTS ADD_TUT_COMPONENT_TEMPLATE_SOURCES)
        CopyTutorialSource(dest "${source}" "" TRUE)
        list(APPEND sources "${dest}")
    endforeach()
    DeclareCAmkESComponent(${name} ${ADD_TUT_COMPONENT_UNPARSED_ARGUMENTS} SOURCES ${sources})
endfunction(DeclareTutorialsCAmkESComponent)

# Wrapper around `DeclareCAmkESRootserver` that takes additional lists of `TUTORIAL_SOURCES` and `TEMPLATE_SOURCES`
# to process and move into the tutorial build directory. Unlike other wrappers the process files are not
# passed through to the invocation of `DeclareCAmkESRootserver` but the intention is that the ADL file
# that is processed and passed to `DeclareCAmkESRootserver` may refer to other files and these should be
# specified in these lists.
function(DeclareTutorialsCAmkESRootserver adl)
    cmake_parse_arguments(PARSE_ARGV 1 ADD_TUT_CAMKES "ADL_IS_TUTORIAL;ADL_IS_TEMPLATE" "" "TUTORIAL_SOURCES;TEMPLATE_SOURCES")
    if (ADD_TUT_CAMKES_ADL_IS_TUTORIAL)
        CopyTutorialSource(adl_dest "${adl}" "" FALSE)
    elseif (ADD_TUT_CAMKES_ADL_IS_TEMPLATE)
        CopyTutorialSource(adl_dest "${adl}" "" TRUE)
    endif()
    foreach(source IN LISTS ADD_TUT_CAMKES_TUTORIAL_SOURCES)
        CopyTutorialSource(dest "${source}" "" FALSE)
    endforeach()
    foreach(source IN LISTS ADD_TUT_CAMKES_TEMPLATE_SOURCES)
        CopyTutorialSource(dest "${source}" "" TRUE)
    endforeach()
    DeclareCAmkESRootserver("${adl_dest}")
endfunction(DeclareTutorialsCAmkESRootserver)