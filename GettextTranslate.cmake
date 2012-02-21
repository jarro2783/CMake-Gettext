# This module does creates build rules for updating translation files made 
# with gettext
# In your top level CMakeLists.txt, do
#   include(GettextTranslate)
# then in any po directory where you want things to be translated, write
#   GettextTranslate()
#
# it reads variables from Makevars, one of the most important being DOMAIN
# it reads the languages to generate from LINGUAS
#
# it adds the following targets
# update-po
# update-gmo
# ${DOMAIN}-pot.update
# generate-${DOMAIN}-${lang}-po
# generate-${DOMAIN}-${lang}-gmo
#
# where ${DOMAIN} is the DOMAIN variable read from Makevars
# and ${lang} is each language mentioned in LINGUAS

# add the update-po and update-gmo targets, the actual files that need to
# depend on this will be added as we go
add_custom_target(update-po)
add_custom_target(update-gmo)

macro(GettextTranslate)

  message(STATUS "gettext translate")

  if (NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/POTFILES.in)
    message(FATAL_ERROR "There is no POTFILES.in in this directory")
  endif()

  if (NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/Makevars)
    message(FATAL_ERROR "There is no Makevars in this directory")
  endif()

  file(STRINGS ${CMAKE_CURRENT_SOURCE_DIR}/Makevars makevars
    REGEX "^[^=]+=(.*)$"
  )

  foreach(makevar ${makevars})
    message(STATUS "makevar: " ${makevar})
    string(REGEX REPLACE "^([^= ]+) =[ ]?(.*)$" "\\1" MAKEVAR_KEY ${makevar})
    string(REGEX REPLACE "^([^= ]+) =[ ]?(.*)$" "\\2" 
      MAKEVAR_${MAKEVAR_KEY} ${makevar})
    message(STATUS split: ${MAKEVAR_KEY}=${MAKEVAR_${MAKEVAR_KEY}})
  endforeach()
  message(STATUS DOMAIN=${MAKEVAR_DOMAIN})

  configure_file(${CMAKE_CURRENT_SOURCE_DIR}/POTFILES.in
    ${CMAKE_CURRENT_BINARY_DIR}/POTFILES
    COPYONLY
  )

  configure_file(${CMAKE_CURRENT_SOURCE_DIR}/LINGUAS
    ${CMAKE_CURRENT_BINARY_DIR}/LINGUAS
    COPYONLY
  )

  #set the directory to not clean
  set_property(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    PROPERTY CLEAN_NO_CUSTOM true)

  file(STRINGS ${CMAKE_CURRENT_SOURCE_DIR}/POTFILES.in potfiles
    REGEX "^[^#].*"
  )

  foreach(potfile ${potfiles})
    message(STATUS "using file: "${MAKEVAR_top_builddir}/${potfile})
    list(APPEND source_translatable 
      ${CMAKE_CURRENT_SOURCE_DIR}/${MAKEVAR_top_builddir}/${potfile})
  endforeach()

  set(TEMPLATE_FILE ${MAKEVAR_DOMAIN}.pot)
  set(TEMPLATE_FILE_ABS ${CMAKE_CURRENT_SOURCE_DIR}/${TEMPLATE_FILE})
  add_custom_target(${MAKEVAR_DOMAIN}.pot-update DEPENDS
    ${TEMPLATE_FILE_ABS}
  )

  message(STATUS "options are " ${MAKEVAR_XGETTEXT_OPTIONS})
  string(REGEX MATCHALL "[^ ]+" XGETTEXT_OPTS ${MAKEVAR_XGETTEXT_OPTIONS})
  add_custom_command(OUTPUT ${TEMPLATE_FILE_ABS}
    COMMAND xgettext ${XGETTEXT_OPTS}
      -o ${TEMPLATE_FILE_ABS} 
      --default-domain=${MAKEVAR_DOMAIN}
      --add-comments=TRANSLATORS:
      --copyright-holder=${MAKEVAR_COPYRIGHT_HOLDER}
      --msgid-bugs-address="${MAKEVAR_MSGID_BUGS_ADDRESS}"
      --directory=${MAKEVAR_top_builddir}
      --files-from=${CMAKE_CURRENT_SOURCE_DIR}/POTFILES.in
      --package-version=${VERSION}
      --package-name=${CMAKE_PROJECT_NAME}
    DEPENDS ${source_translatable}
    ${CMAKE_CURRENT_SOURCE_DIR}/POTFILES.in
    #    VERBATIM
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  )

  add_dependencies(update-po ${MAKEVAR_DOMAIN}.pot-update)

  file(STRINGS ${CMAKE_CURRENT_SOURCE_DIR}/LINGUAS LINGUAS 
      REGEX "^[^#].*")
  message(STATUS "stripped languages: " ${LINGUAS})
  string(REGEX MATCHALL "[^ ]+" languages ${LINGUAS})

  foreach(lang ${languages})
    message(STATUS "language: "${lang})

    set(PO_FILE_NAME "${CMAKE_CURRENT_SOURCE_DIR}/${lang}.po")
    set(GMO_FILE_NAME "${CMAKE_CURRENT_SOURCE_DIR}/${lang}.gmo")
    set(PO_TARGET "generate-${MAKEVAR_DOMAIN}-${lang}-po")
    set(GMO_TARGET "generate-${MAKEVAR_DOMAIN}-${lang}-gmo")
    list(APPEND po_files ${PO_TARGET})
    list(APPEND gmo_files ${GMO_TARGET})

    if(${lang} MATCHES "en@(.*)quot")

      add_custom_command(OUTPUT ${lang}.insert-header
        COMMAND
        sed -e "'/^#/d'" -e 's/HEADER/${lang}.header/g'
        ${CMAKE_CURRENT_SOURCE_DIR}/insert-header.sin > ${lang}.insert-header
      )

      #generate the en@quot files
      add_custom_command(OUTPUT ${PO_FILE_NAME}
        COMMAND
        msginit -i ${TEMPLATE_FILE_ABS} --no-translator -l ${lang} 
        -o - 2>/dev/null
        | sed -f ${CMAKE_CURRENT_BINARY_DIR}/${lang}.insert-header 
        | msgconv -t UTF-8 
        | msgfilter sed -f ${CMAKE_CURRENT_SOURCE_DIR}/`echo ${lang} 
        | sed -e 's/.*@//'`.sed 2>/dev/null >
        ${PO_FILE_NAME}
        DEPENDS ${lang}.insert-header ${TEMPLATE_FILE_ABS}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
      )

    else()

      message(STATUS "${lang}.po depends on ${TEMPLATE_FILE_ABS}")
      add_custom_command(OUTPUT ${PO_FILE_NAME}
        COMMAND ${GETTEXT_MSGMERGE_EXECUTABLE} --lang=${lang}
          ${PO_FILE_NAME} ${TEMPLATE_FILE_ABS} 
          -o ${PO_FILE_NAME}.new
        COMMAND mv ${PO_FILE_NAME}.new ${PO_FILE_NAME}
        DEPENDS ${TEMPLATE_FILE_ABS}
      )

    endif()

    message(STATUS "${lang}.gmo depends on
      ${CMAKE_CURRENT_SOURCE_DIR}/${lang}.po")
    add_custom_command(OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/${lang}.gmo
      COMMAND ${GETTEXT_MSGFMT_EXECUTABLE} -c --statistics --verbose -o
        ${CMAKE_CURRENT_SOURCE_DIR}/${lang}.gmo
        ${CMAKE_CURRENT_SOURCE_DIR}/${lang}.po
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${lang}.po
    )
    add_custom_target(${GMO_TARGET} DEPENDS ${GMO_FILE_NAME})

    add_custom_target(${PO_TARGET} DEPENDS ${PO_FILE_NAME})

    install(FILES ${GMO_FILE_NAME} DESTINATION
      ${LOCALEDIR}/${lang}/LC_MESSAGES
      RENAME ${MAKEVAR_DOMAIN}.mo
    )

  endforeach()

  message(STATUS "target update-po depends on ${po_files}")
  add_dependencies(update-po ${po_files})
  message(STATUS "target update-gmo depends on ${gmo_files}")
  add_dependencies(update-gmo ${gmo_files})

#string(REGEX MATCH "^[^=]+=(.*)$" parsed_variables ${makevars})

endmacro()
