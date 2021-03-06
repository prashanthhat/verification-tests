Feature: stibuild.feature

  # @author haowang@redhat.com
  # @case_id OCP-11099
  Scenario: STI build with invalid context dir
    Given I have a project
    When I run the :new_app client command with:
      | file | <%= BushSlicer::HOME %>/testdata/image/language-image-templates/python-27-rhel7-errordir-stibuild.json |
    Then the step should succeed
    When I run the :start_build client command with:
      | buildconfig | python-sample-build |
    And the "python-sample-build-1" build was created
    And the "python-sample-build-1" build failed
    When I run the :get client command with:
      | resource | build |
    Then the output should contain:
      | InvalidContextDirectory |

  # @author xiuwang@redhat.com
  Scenario Outline: Trigger s2i/docker/custom build using additional imagestream
    Given I have a project
    And I run the :new_app client command with:
      | file | <%= BushSlicer::HOME %>/testdata/templates/<template> |
    Then the step should succeed
    And the "sample-build-1" build was created
    When I run the :cancel_build client command with:
      | build_name | sample-build-1                  |
    Then the step should succeed
    When I run the :import_image client command with:
      | image_name | myimage               |
      | from       | centos/ruby-25-centos7|
      | confirm    | true                  |
    Then the step should succeed
    And the "sample-build-2" build was created
    When I run the :describe client command with:
      | resource | builds         |
      | name     | sample-build-2 |
    Then the step should succeed
    And the output should contain:
      |Build trigger cause:	Image change          |
      |Image ID:		centos/ruby-25-centos7|
      |Image Name/Kind:	myimage:latest                |
    When I run the :start_build client command with:
      | buildconfig | sample-build |
    Then the step should succeed
    And the "sample-build-3" build was created
    When I get project builds
    Then the step should succeed
    And the output should not contain "sample-build-4"

    Examples:
      | template                      |
      | tc498848/tc498848-s2i.json    | # @case_id OCP-12041
      | tc498847/tc498847-docker.json | # @case_id OCP-11911
      | tc498846/tc498846-custom.json | # @case_id OCP-11739

  # @author wewang@redhat.com
  # @case_id OCP-15464
  Scenario:Override incremental setting using --incremental flag when s2i build request
    Given I have a project
    When I run the :new_app client command with:
      | app_repo | openshift/ruby:2.3~https://github.com/openshift/ruby-hello-world.git |
    Then the step should succeed
    And the "ruby-hello-world-1" build was created
    And the "ruby-hello-world-1" build completed
    When I run the :patch client command with:
      | resource      | bc                                                            |
      | resource_name | ruby-hello-world                                              |
      | p             | {"spec":{"strategy":{"sourceStrategy":{"incremental":true}}}} |
    Then the step should succeed
    When I run the :describe client command with:
      | resource | buildconfig      |
      | name     | ruby-hello-world |
    Then the step should succeed
    Then the output should match "Incremental Build:\s+yes"
    When I run the :start_build client command with:
      | buildconfig | ruby-hello-world |
      | incremental | true             |
      Then the step should succeed
    When I run the :logs client command with:
      | resource_name | bc/ruby-hello-world |
    Then the output should contain:
      | save-artifacts: No such file or directory|
     When I run the :start_build client command with:
      | buildconfig | ruby-hello-world |
      | incremental | false            |
      Then the step should succeed
    When I run the :logs client command with:
      | resource_name | bc/ruby-hello-world |
    Then the output should not contain:
      | save-artifacts: No such file or directory|

  # @author wzheng@redhat.com
  # @case_id OCP-11120
  Scenario: STI build with dockerImage with specified tag
    Given I have a project
    When I run the :new_app client command with:
      | docker_image | centos/ruby-25-centos7                  |
      | app_repo     | https://github.com/openshift-qe/ruby-ex |
    Then the step should succeed
    And the "ruby-ex-1" build completes
    When I run the :patch client command with:
      | resource      | buildconfig                                                                                                                                      |
      | resource_name | ruby-ex                                                                                                                                          |
      | p             | {"spec": {"strategy": {"sourceStrategy": {"from": {"kind": "DockerImage","name": "docker.io/centos/ruby-25-centos7:latest"}}},"type": "Source"}} |
    Then the step should succeed
    When I run the :start_build client command with:
      | buildconfig | ruby-ex |
    Then the step should succeed
    And the "ruby-ex-2" build completes
    Then the step should succeed
    When I run the :patch client command with:
      | resource      | buildconfig                                                                                                                                     |
      | resource_name | ruby-ex                                                                                                                                         |
      | p             | {"spec": {"strategy": {"sourceStrategy": {"from": {"kind": "DockerImage","name": "docker.io/centos/ruby-25-centos7:error"}}},"type": "Source"}} |
    Then the step should succeed
    When I run the :start_build client command with:
      | buildconfig | ruby-ex |
    Then the step should succeed
    And the "ruby-ex-3" build failed
    When I run the :describe client command with:
      | resource | build     |
      | name     | ruby-ex-3 |
    Then the step should succeed
    And the output should contain "error"

  # @author wzheng@redhat.com
  # @case_id OCP-22596
  Scenario: Create app with template eap72-basic-s2i with jbosseap rhel7 image
    Given I have a project
    When I run the :new_app client command with:
      | template | eap72-basic-s2i |
    Then the step should succeed
    Given the "eap-app-1" build was created
    And the "eap-app-1" build completed
    Given 1 pods become ready with labels:
      | application=eap-app |

  # @author xiuwang@redhat.com
  # @case_id OCP-28891
  Scenario: Test s2i build in disconnect cluster 
    Given I have a project
    When I have an http-git service in the project
    And I run the :set_env client command with:
      | resource | dc/git               |
      | e        | REQUIRE_SERVER_AUTH= |
      | e        | REQUIRE_GIT_AUTH=    |
    Then the step should succeed
    When a pod becomes ready with labels:
      | deploymentconfig=git |
      | deployment=git-2     |
    When I run the :cp client command with:
      | source | <%= BushSlicer::HOME %>/testdata/build/httpd-ex.git | 
      | dest   | <%= pod.name %>:/var/lib/git/                       |
    Then the step should succeed
    When I run the :new_app client command with:
      | app_repo | openshift/httpd:latest~http://<%= cb.git_route %>/httpd-ex.git |
    Then the step should succeed
    Given the "httpd-ex-1" build was created
    And the "httpd-ex-1" build completes
