
function( fckit_target_append_fypp_args output target )
  unset(_args)
  if( CMAKE_VERSION VERSION_LESS 3.12 ) # Hopefully we can remove this soon
    if( TARGET ${target} )
      foreach( include_property INCLUDE_DIRECTORIES;INTERFACE_INCLUDE_DIRECTORIES )
        set( prop "$<TARGET_PROPERTY:${target},${include_property}>" )
        list( APPEND _args "$<$<BOOL:${prop}>:-I $<JOIN:${prop}, -I >>" )
      endforeach()
      foreach( definitions_property COMPILE_DEFINITIONS;INTERFACE_COMPILE_DEFINITIONS )
        set( prop "$<TARGET_PROPERTY:${target},${definitions_property}>" )
        list( APPEND _args "$<$<BOOL:${prop}>:-D $<JOIN:${prop}, -D >>" )
      endforeach()
    endif()
  else()
    set( valid_target TRUE )
    if( target MATCHES "/" )
      set( valid_target FALSE )
    endif()
    if( valid_target )
      foreach( include_property INCLUDE_DIRECTORIES;INTERFACE_INCLUDE_DIRECTORIES )
        set( prop "$<$<TARGET_EXISTS:${target}>:$<TARGET_PROPERTY:${target},${include_property}>>" )
        list( APPEND _args "$<$<BOOL:${prop}>:-I $<JOIN:${prop}, -I >>" )
      endforeach()
      foreach( definitions_property COMPILE_DEFINITIONS;INTERFACE_COMPILE_DEFINITIONS )
        set( prop "$<$<TARGET_EXISTS:${target}>:$<TARGET_PROPERTY:${target},${definitions_property}>>" )
        list( APPEND _args "$<$<BOOL:${prop}>:-D $<JOIN:${prop}, -D >>" )
      endforeach()
    endif()
  endif()
  # Append to output and set in parent scope
  if( _args )
    set(${output} ${${output}} ${_args} PARENT_SCOPE)
  endif()
endfunction()

function( fckit_preprocess_fypp_sources output )

  set( options NO_LINE_NUMBERING )
  set( single_value_args "" )
  set( multi_value_args SOURCES FYPP_ARGS DEPENDS )
  cmake_parse_arguments( _PAR "${options}" "${single_value_args}" "${multi_value_args}"  ${_FIRST_ARG} ${ARGN} )

  unset( outfiles )

  foreach( filename ${_PAR_SOURCES} )

    get_filename_component( dir ${filename} DIRECTORY )
    get_filename_component( base ${filename} NAME_WE )
    set( outfile ${CMAKE_CURRENT_BINARY_DIR} )
    if( dir )
      set( outfile "${outfile}/${dir}" )
    endif()
    set( outfile "${outfile}/${base}.F90" )

    list( APPEND outfiles ${outfile} )

    unset(args)
    list( APPEND args -l 132 ) # Line length
    list( APPEND args -p )     # Create parent folder
    set( _enable_line_numbers TRUE )
    if( _PAR_NO_LINE_NUMBERING OR FYPP_NO_LINE_NUMBERING )
      set( _enable_line_numbers FALSE )
    endif()
    if( CMAKE_Fortran_COMPILER_ID MATCHES "Cray" )
      set( _enable_line_numbers FALSE )
      # Compiler errors occur (tested with cce/8.7.5 )
    endif()
    if( _enable_line_numbers )
      list( APPEND args -n )   # Create line numbering for compile errors
      # list( APPEND args -N nocontlines )  # workaround for line numbers in continuation lines
    endif()

    if( _PAR_FYPP_ARGS )
        set( args ${args} ${_PAR_FYPP_ARGS} )
    endif()

    foreach( target ${_PAR_DEPENDS} )
      fckit_target_append_fypp_args( args ${target} )
    endforeach()

    if( dir )
      set( short_outfile "${dir}/${base}.F90" )
    else()
      set( short_outfile "${base}.F90")
    endif()

    add_custom_command(
      OUTPUT ${outfile}
      COMMAND ${FYPP} ${args} ${CMAKE_CURRENT_SOURCE_DIR}/${filename} ${outfile}
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${filename} ${_PAR_DEPENDS} 
      COMMENT "[fypp] Preprocessor generating ${short_outfile}" )

    set_source_files_properties(${outfile} PROPERTIES GENERATED TRUE)

  endforeach()

  # Append to output and set in parent scope
  set(${output} ${${output}} ${outfiles} PARENT_SCOPE)


endfunction()

function( fckit_target_preprocess_fypp _PAR_TARGET )

  set( options NO_LINE_NUMBERING )
  set( single_value_args "" )
  set( multi_value_args FYPP_ARGS DEPENDS )
  cmake_parse_arguments( _PAR "${options}" "${single_value_args}" "${multi_value_args}"  ${_FIRST_ARG} ${ARGN} )

  if( TARGET ${_PAR_TARGET} )

      get_target_property( _target_sources ${_PAR_TARGET} SOURCES )

      unset( sources_to_be_preprocessed )
      foreach( source ${_target_sources} )
        if( source MATCHES ".fypp.F90" )
          list( APPEND sources_to_be_preprocessed ${source} )
        elseif( source MATCHES ".F90.fypp" )
          list( APPEND sources_to_be_preprocessed ${source} )
        elseif( source MATCHES ".fypp" )
          list( APPEND sources_to_be_preprocessed ${source} )
        endif()
      endforeach()
      foreach( source ${sources_to_be_preprocessed} )
        set( source_files_properties ${source} PROPERTIES HEADER_FILE_ONLY TRUE )
      endforeach()

### BUG (tested upto 3.13.2)
#   Even though source files to be preprocessed with final extension .F90 have just been
#   declared as HEADER_FILE_ONLY, CMake still tries to compile these files.
#   This does not happen for files ending with other extensions ( .fypp )
      set( _create_fypp_target FALSE )
      foreach( source ${sources_to_be_preprocessed} )
        if( source MATCHES ".fypp.F90" )
          set( _create_fypp_target TRUE )
          list(FILTER _target_sources EXCLUDE REGEX ${source} )
        endif()
      endforeach()
      if( NOT TARGET ${_PAR_TARGET}_fypp AND _create_fypp_target )
          set_property( TARGET ${_PAR_TARGET} PROPERTY SOURCES ${_target_sources} )
          add_custom_target( ${_PAR_TARGET}_fypp SOURCES ${sources_to_be_preprocessed} )
      endif()
### END BUG



      foreach( depends_property LINK_DEPENDS;MANUALLY_ADDED_DEPENDENCIES )
        get_target_property( target_depends ${_PAR_TARGET} ${depends_property} )
        if( target_depends )
          set( preprocessed_depends ${preprocessed_depends} ${target_depends} )
        endif()
      endforeach()

      fckit_target_append_fypp_args( args ${_PAR_TARGET} )
   
      fckit_preprocess_fypp_sources( preprocessed_sources
          SOURCES ${sources_to_be_preprocessed}
          FYPP_ARGS ${_PAR_FYPP_ARGS} ${args}
          DEPENDS ${preprocessed_depends} ${_PAR_DEPENDS}
      )

      target_sources( ${_PAR_TARGET} PRIVATE ${preprocessed_sources} )

  endif()

endfunction()