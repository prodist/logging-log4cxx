#! /bin/bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

##
# Prepare a release.
#
# We need to update dates and version numbers at various places during releases and things can go 
# wrong, so another RC might need to be released. Am not sure if/how those things are properly
# handled using the Maven release plugin, because that moves versions of the current branch forward
# and doesn't seem to provide a way to say that a new release is just another RC for some former
# release. Additionally, after the current branch has been moved forward, it might have been used to
# merge new changes already. So hoe to tell Maven to do another release with a former version?
#
# So the current approach of this script is to always create a new branch "next_stable" which acts
# as the base for releases only. One need to manually merge changes to the codebase into that branch
# as needed for making a release work, but keep all other changes to "master" etc. outside. We try
# to handle setting release dates, current number of release candidate etc. here automatically as 
# much as possible. Some of that info is even merged back into some source branch, e.g. "master",
# because release dates in files like "src/changes/changes.xml" need to be updated with additional
# candidates or later releases.
#
# This script can be invoked with "next_stable" being the current branch already or with some other
# and "next_stable" is checked out automatically. If it's invoked with some other branch, release
# dates, new development version etc. are merged to the branch the script was invoked with. Without
# another branch those changes need to be done/merged manually to wherever they need to be in the
# end, most likely "master".
#

function main()
{
  exit_on_changes

  branch_starting=$(      git branch | grep "\*" | cut -d " " -f 2)
  branch_starting_is_ns=$(git branch | grep "\* next_stable")

  co_next_stable
  set_release_date_if
  update_scm_tag_name_format

  exec_maven
  exit_on_started_with_ns

  exit_on_no_new_release_cycle)
  proc_new_release_cycle
}

function exit_on_changes()
{
  if [[ -n $(git status --short) || -n $(git diff-index HEAD) ]]
  then
    echo Maven release process requires committed changes!
    exit 1
  fi
}

function co_next_stable()
{
  if [ -z "${branch_starting_is_ns}" ]
  then
    # If we didn't start with "next_stable", don't merge the starting branch, because it contains
    # changes regarding new development iteration etc. we don't want to have. People need to merge
    # relevant changes manually.
    git checkout "next_stable" || git checkout -b "next_stable"
  fi
}

function set_release_date_if()
{
  local today=$(date "+%Y-%m-%d")
  sed -i -r "1,/date=\".+?\"/ s/date=\".+?\"/date=\"${today}\"/" "src/changes/changes.xml"
  git add "src/changes/changes.xml"

  if ! git diff-index --quiet HEAD
  then
    git commit -m "Set release date to today."
    if [ -z "${branch_starting_is_ns}" ]
    then
      local commit_changes=$(git log --max-count=1 | grep "commit" | cut -d " " -f 2)
      git checkout "${branch_starting}"
      git merge    "${commit_changes}"
      git checkout "next_stable"
    fi
  fi
}

function update_scm_tag_name_format()
{
  local scm_tag_name_format=$(grep "<tagNameFormat>" "pom.xml")
  local scm_tag_name_format_needs_one=$(echo "${scm_tag_name_format}" | grep -E -e "-RCx")
  local scm_tag_name_format_needs_inc=$(echo "${scm_tag_name_format}" | grep -E -e "-RC[0-9]+" | sed -r "s/.+?-RC([0-9]+).+?/\1/")

  if [ -n "${scm_tag_name_format_needs_one}" ]
  then
    sed -i -r "s/(<tagNameFormat>.+?-RC)x/\11/" "pom.xml"
  fi
  if [ -n "${scm_tag_name_format_needs_inc}" ]
  then
    local inced_nr=$((${scm_tag_name_format_needs_inc} + 1))
    sed -i -r "s/(<tagNameFormat>.+?-RC)[0-9]+/\1${inced_nr}/" "pom.xml"
  fi

  git add "pom.xml"
  git commit -m "scm.tagNameFormat reconfigured to new RC number."
}

function exec_maven
{
  mvn clean                          || exit 1
  mvn release:prepare -Dresume=false || exit 1
}

function exit_on_started_with_ns
{
  if [ -n "${branch_starting_is_ns}" ]
  then
    exit 0
  fi
}

function exit_on_no_new_release_cycle()
{
  git checkout "${branch_starting}"
  local new_release_cycle=$(grep 'date="XXXX-XX-XX"' "src/changes/changes.xml")

  if [ -n "${new_release_cycle}" ]
  then
    git checkout "next_stable"
    exit 0
  fi
}

function proc_new_release_cycle()
{
  git checkout "${branch_starting}"

  local commit_mvn_next_dev_iter=${1}
  local new_dev_ver=$(      grep -E "^project.dev.log4cxx" "release.properties" | cut -d "=" -f 2)
  local new_dev_ver_short=$(grep -E "^project.dev.log4cxx" "release.properties" | cut -d "=" -f 2 | cut -d "-" -f 1)
  local new_release=$(cat <<-"END"
	<body>\n\
		<release	version="VER_NEEDED"\n\
					date="XXXX-XX-XX"\n\
					description="Maintenance release">\n\
		<\/release>\n
END
)
  local new_release="${new_release/VER_NEEDED/${new_dev_ver_short}}"

  sed -i -r "s/AC_INIT\(\[log4cxx\], \[.+?\]\)/AC_INIT([log4cxx], [${new_dev_ver_short}])/" "configure.ac"
  sed -i -r "s/(<version>).+(<)/\1${new_dev_ver}\2/"                                        "pom.xml"
  sed -i -r "s/<body>/${new_release}/"                                                      "src/changes/changes.xml"

  git add "configure.ac"
  git add "pom.xml"
  git add "src/changes/changes.xml"

  if ! git diff-index --quiet HEAD
  then
    git commit -m "Prepare for next development iteration: ${new_dev_ver_short}"
  fi

  git checkout "next_stable"
}

main
