Feature: pod related features

  # @author xiuli@redhat.com
  # @case_id OCP-15808
  Scenario: Endpoints should update in time and no delay
    Given I have a project
    When I run the :create client command with:
      | f | <%= BushSlicer::HOME %>/testdata/networking/list_for_pods.json |
    Then the step should succeed
    When a pod becomes ready with labels:
      | name=test-pods|
    Then I wait for the "test-service" endpoint to appear up to 5 seconds

  # @author pruan@redhat.com
  # @case_id OCP-12432
  @admin
  Scenario: Expose shared memory of the pod--Clustered
    Given I have a project
    When I run the :new_app client command with:
      | app_repo | openshift/deployment-example |
    Then the step should succeed
    Given a pod becomes ready with labels:
      | app=deployment-example |
    Given I use the "<%= pod.node_name %>" node
    Given the system container id for the pod is stored in the clipboard
    And evaluation of `pod.container(user: user, name: 'deployment-example').id` is stored in the :container_id clipboard
    When I run commands on the host:
      | docker inspect <%= cb.container_id %> \|grep Mode |
    Then the step should succeed
    And the output should contain:
      | "NetworkMode": "container:<%= cb.system_pod_container_id %> |
      | "IpcMode": "container:<%= cb.system_pod_container_id %>     |
    When I run commands on the host:
      | docker inspect <%= cb.container_id %> \|grep Pid |
    Then the step should succeed
    And evaluation of `/"Pid":\s+(\d+)/.match(@result[:response])[1]` is stored in the :user_container_pid clipboard
    When I run commands on the host:
      | docker inspect <%= cb.system_pod_container_id %> \|grep Pid |
    Then the step should succeed
    And evaluation of `/"Pid":\s+(\d+)/.match(@result[:response])[1]` is stored in the :system_container_pid clipboard
    When I run commands on the host:
      | ls -l /proc/<%= cb.system_container_pid %>/ns |
    Then the step should succeed
    And evaluation of `/ipc:\[(\d+)\]/.match(@result[:response])[1]` is stored in the :system_ipc clipboard
    And evaluation of `/net:\[(\d+)\]/.match(@result[:response])[1]` is stored in the :system_net clipboard
    When I run commands on the host:
      | ls -l /proc/<%= cb.user_container_pid %>/ns |
    Then the step should succeed
    And evaluation of `/ipc:\[(\d+)\]/.match(@result[:response])[1]` is stored in the :user_ipc clipboard
    And evaluation of `/net:\[(\d+)\]/.match(@result[:response])[1]` is stored in the :user_net clipboard
    Then the expression should be true> cb.system_ipc == cb.user_ipc
    Then the expression should be true> cb.system_net == cb.user_net

  # @author chezhang@redhat.com
  # @case_id OCP-10598
  @admin
  @destructive
  Scenario: Existing pods will not be affected when node is unschedulable
    Given I have a project
    When I run the :create client command with:
      | f | https://raw.githubusercontent.com/openshift/origin/master/examples/hello-openshift/hello-pod.json |
    Then the step should succeed
    And the pod named "hello-openshift" status becomes :running
    And evaluation of `pod.node_name` is stored in the :pod_node clipboard
    And evaluation of `pod.ip` is stored in the :pod_ip clipboard
    When I run the :create client command with:
      | f | <%= BushSlicer::HOME %>/testdata/pods/pod-pull-by-tag.yaml |
    Then the step should succeed
    And the pod named "pod-pull-by-tag" status becomes :running
    Given node schedulable status should be restored after scenario
    When I run the :oadm_cordon_node admin command with:
      | node_name | <%= cb.pod_node %> |
    Then the step should succeed
    When I execute on the pod:
      | bash |
      | -c   |
      | curl http://<%= cb.pod_ip %>:8080 |
    Then the step should succeed
    And the output should contain:
      | Hello OpenShift |

  # @author chezhang@redhat.com
  # @case_id OCP-10345
  @admin
  @destructive
  Scenario: pod node label selector must be consistent with its project node label selector
    Given I have a project
    Given a 5 characters random string of type :dns is stored into the :proj_name clipboard
    When I run the :oadm_new_project admin command with:
      | project_name  | <%= cb.proj_name %> |
      | node_selector | os=rhel             |
      | admin         | <%= user.name %>    |
    Then the step should succeed
    When I run the :create admin command with:
      | f | <%= BushSlicer::HOME %>/testdata/pods/pod-with-nodeselector.yaml |
      | n | <%= cb.proj_name %>                                                                                |
    Then the step should fail
    And the output should contain "pod node label selector conflicts with its project node label selector"

  # @author chezhang@redhat.com
  # @case_id OCP-11116
  @admin
  @destructive
  Scenario: New pods creation will be disabled on unschedulable nodes
    Given I have a project
    Given I store the schedulable nodes in the :nodes clipboard
    Given node schedulable status should be restored after scenario
    When I run the :oadm_cordon_node admin command with:
      | node_name | noescape: <%= cb.nodes.map(&:name).join(" ") %> |
    Then the step should succeed
    When I run the :create client command with:
      | f | https://raw.githubusercontent.com/openshift/origin/master/examples/hello-openshift/hello-pod.json |
    Then the step should succeed
    And the pod named "hello-openshift" status becomes :pending
    Then I wait for the steps to pass:
    """
    When I run the :describe client command with:
      | resource | pod             |
      | name     | hello-openshift |
    Then the output should match:
      | FailedScheduling.*(no nodes available to schedule pods\|0/[\d] nodes are available) |
    """
    When I get project events
    Then the output should match:
      | hello-openshift.*(no nodes available to schedule pods\|0/[\d] nodes are available) |

  # @author chezhang@redhat.com
  # @case_id OCP-11466
  @admin
  @destructive
  Scenario: Recovering an unschedulable node
    Given I have a project
    Given I run the :patch admin command with:
      | resource | namespace |
      | resource_name | <%=project.name%> |
      | p | {"metadata":{"annotations": {"openshift.io/node-selector": ""}}}|
    Then the step should succeed
    Given I store the schedulable nodes in the :nodes clipboard
    Given node schedulable status should be restored after scenario
    When I run the :oadm_cordon_node admin command with:
      | node_name | <%= cb.nodes[0].name %> |
    Then the step should succeed
    Given label "os=fedora" is added to the "<%= cb.nodes[0].name %>" node
    When I run the :create client command with:
      | f | <%= BushSlicer::HOME %>/testdata/pods/pod-with-nodeselector.yaml |
    Then the step should succeed
    And the pod named "hello-pod" status becomes :pending
    When I run the :oadm_uncordon_node admin command with:
      | node_name | <%= cb.nodes[0].name %> |
    Then the step should succeed
    And the pod named "hello-pod" status becomes :running

  # @author chezhang@redhat.com
  # @case_id OCP-11752
  @admin
  Scenario: Pod will not be copied to nodes which does not match it's node selector
    Given I have a project
    Given I run the :patch admin command with:
      | resource | namespace |
      | resource_name | <%=project.name%> |
      | p | {"metadata":{"annotations": {"openshift.io/node-selector": ""}}}|
    Then the step should succeed
    Given I store the schedulable nodes in the :nodes clipboard
    Given label "daemon=yes" is added to the "<%= cb.nodes[0].name %>" node
    Given cluster role "cluster-admin" is added to the "first" user
    When I run the :create client command with:
      | f | <%= BushSlicer::HOME %>/testdata/daemon/daemonset-nodeselector.yaml |
    Then the step should succeed
    And I wait up to 120 seconds for the steps to pass:
    """
    When I run the :describe client command with:
      | resource | daemonset       |
      | name     | hello-daemonset |
    Then the output should match "1 Running.*0 Waiting.*0 Succeeded.*0 Failed"
    """
    When I run the :get client command with:
      | resource | po   |
      | o        | yaml |
    Then the output should match:
      | nodeName: <%= cb.nodes[0].name %> |

  # @author chezhang@redhat.com
  # @case_id OCP-11925
  @admin
  @destructive
  Scenario: Pods will still be created by DaemonSet when nodes are SchedulingDisabled
    Given I have a project
    Given I store the schedulable workers in the :nodes clipboard
    Given node schedulable status should be restored after scenario
    When I run the :oadm_cordon_node admin command with:
      | node_name | <%= cb.nodes[0].name %> |
    Then the step should succeed
    Given cluster role "cluster-admin" is added to the "first" user
    When I run the :create client command with:
      | f | <%= BushSlicer::HOME %>/testdata/daemon/daemonset.yaml |
    Then the step should succeed
    Then I wait up to 60 seconds for the steps to pass:
    """
    When I run the :describe client command with:
      | resource | daemonset       |
      | name     | hello-daemonset |
    Then the output should match "0 Waiting.*0 Succeeded.*0 Failed"
    """
    When I run the :get client command with:
      | resource | po   |
      | o        | yaml |
    Then the output should match:
      | nodeName: <%= cb.nodes[0].name %> |

  # @author chezhang@redhat.com
  # @author weinliu@redhat.com
  # @case_id OCP-12047
  @admin
  Scenario: When node labels change, DaemonSet will add pods to newly matching nodes and delete pods from not-matching nodes
    Given I have a project
    Given I run the :patch admin command with:
      | resource | namespace |
      | resource_name | <%=project.name%> |
      | p | {"metadata":{"annotations": {"openshift.io/node-selector": ""}}}|
    Then the step should succeed
    Given I store the schedulable workers in the :nodes clipboard
    Given environment has at least 2 schedulable nodes
    Given label "daemon=yes" is added to the "<%= cb.nodes[0].name %>" node
    Given label "daemon=no" is added to the "<%= cb.nodes[1].name %>" node
    Given cluster role "cluster-admin" is added to the "first" user
    When I run the :create client command with:
      | f | <%= BushSlicer::HOME %>/testdata/daemon/daemonset-nodeselector.yaml |
    Then the step should succeed
    And I wait for the steps to pass:
    """
    When I run the :describe client command with:
      | resource | daemonset       |
      | name     | hello-daemonset |
    Then the output should match "1 Running.*0 Waiting.*0 Succeeded.*0 Failed"
    """
    When I run the :get client command with:
      | resource | po   |
      | o        | yaml |
    Then the output should match:
      | nodeName: <%= cb.nodes[0].name %> |
    When I run the :label admin command with:
      | resource  | node                    |
      | name      | <%= cb.nodes[0].name %> |
      | key_val   | daemon=no               |
      | overwrite | true                    |
    Then the step should succeed
    When I run the :label admin command with:
      | resource  | node                    |
      | name      | <%= cb.nodes[1].name %> |
      | key_val   | daemon=yes              |
      | overwrite | true                    |
    Then the step should succeed
    And I wait for the steps to pass:
    """
    When I run the :get client command with:
      | resource | po   |
      | o        | yaml |
    Then the output should match:
      | nodeName: <%= cb.nodes[1].name %> |
    """

  # @author chezhang@redhat.com
  # @case_id OCP-12338
  @admin
  @destructive
  Scenario: Secret is valid after node reboot
    Given I have a project
    Given I run the :patch admin command with:
      | resource | namespace |
      | resource_name | <%=project.name%> |
      | p | {"metadata":{"annotations": {"openshift.io/node-selector": ""}}}|
    Then the step should succeed
    Given SCC "privileged" is added to the "default" user
    Given I store the schedulable nodes in the :nodes clipboard
    When I run the :create client command with:
      | f | <%= BushSlicer::HOME %>/testdata/secrets/tc483170/secret-nginx-2.yaml |
    Then the step should succeed
    When I run the :get client command with:
      | resource      | secret         |
      | resource_name | secret-nginx-2 |
    Then the output should match:
      | secret-nginx-2\\s+Opaque\\s+2  |
    When I run the :describe client command with:
      | resource | secret         |
      | name     | secret-nginx-2 |
    Then the output should match:
      | password:\\s+11 bytes |
      | username:\\s+9 bytes  |
    When I run oc create over "<%= BushSlicer::HOME %>/testdata/secrets/tc483170/secret-pod-nginx-2.yaml" replacing paths:
      | ["spec"]["nodeName"] | <%= cb.nodes[0].name %> |
    And the step should succeed
    Given the pod named "secret-pod-nginx-2" becomes ready
    When I execute on the pod:
      | cat | /etc/secret-volume-2/password | /etc/secret-volume-2/username |
    Then the step should succeed
    And the output by order should match:
      | value-2 |
      | value-1 |
    When I run the :patch client command with:
      | resource      | secret                                                                   |
      | resource_name | secret-nginx-2                                                           |
      | p             | { "data": { "password": null, "username": "dXNlcm5hbWVjaGFuZ2VkCg==" } } |
    Then the step should succeed
    When I run the :get client command with:
      | resource      | secret         |
      | resource_name | secret-nginx-2 |
    Then the output should match:
      | secret-nginx-2\\s+Opaque\\s+1  |
    When I run the :describe client command with:
      | resource | secret         |
      | name     | secret-nginx-2 |
    Then the output should match:
      | username:\\s+16 bytes |
    When I execute on the pod:
      | cat | /etc/secret-volume-2/password | /etc/secret-volume-2/username |
    Then the step should succeed
    And the output by order should match:
      | value-2 |
      | value-1 |
    Given I use the "<%= cb.nodes[0].name %>" node
    And the host is rebooted and I wait it up to 600 seconds to become available
    And I wait up to 500 seconds for the steps to pass:
    """
    When I execute on the pod:
      | cat | /etc/secret-volume-2/username |
    Then the step should succeed
    And the output should match:
      | usernamechanged |
    """

  # @author chezhang@redhat.com
  # @case_id OCP-11595
  @admin
  @destructive
  Scenario: Should show image digests in node status
    Given I store the schedulable nodes in the :nodes clipboard
    Given I use the "<%= cb.nodes[0].name %>" node
    Given I run commands on the host:
      | docker pull docker.io/openshift/mysql-56-centos7@sha256:3fd34fda8d10cae95a1e0756d90a8f7d5bc7b90d25ab65549a72ad2206cae92f                                               |
      | docker pull docker.io/openshift/hello-openshift@sha256:05bbc54e84a393be64dc3acde9f7d350b52e9e8bc21e5798c6b27c702aa4a155                                                |
      | docker pull openshift/ruby-20-centos7:latest                                                                                                                           |
      | docker pull openshift/python-33-centos7:latest                                                                                                                         |
      | docker images --digests \| grep -E "docker.io/openshift/mysql-56-centos7\|docker.io/openshift/hello-openshift\|openshift/ruby-20-centos7\|openshift/python-33-centos7" |
    Then the step should succeed
    And I wait up to 120 seconds for the steps to pass:
    """
    When I run the :get admin command with:
      | resource      | no                      |
      | resource_name | <%= cb.nodes[0].name %> |
      | o             | yaml                    |
    Then the output should contain:
      | docker.io/openshift/mysql-56-centos7@sha256:3fd34fda8d10cae95a1e0756d90a8f7d5bc7b90d25ab65549a72ad2206cae92f |
      | docker.io/openshift/hello-openshift@sha256:05bbc54e84a393be64dc3acde9f7d350b52e9e8bc21e5798c6b27c702aa4a155  |
      | openshift/ruby-20-centos7:latest                                                                             |
      | openshift/python-33-centos7:latest                                                                           |
    """
    Given I use the "<%= cb.nodes[0].name %>" node
    Given I run commands on the host:
      | docker rmi -f openshift/ruby-20-centos7:latest                     |
      | docker images --digests \| grep "openshift/ruby-20-centos7:latest" |
    Then the step should fail
    And I wait up to 120 seconds for the steps to pass:
    """
    When I run the :get admin command with:
      | resource      | no                      |
      | resource_name | <%= cb.nodes[0].name %> |
      | o             | yaml                    |
    Then the output should not contain:
      | openshift/ruby-20-centos7:latest |
    """

  # @author chezhang@redhat.com
  # @case_id OCP-13374
  @admin
  Scenario: Pod and container level selinuxoptions should both work
    Given I have a project
    Given SCC "privileged" is added to the "default" user
    When I run the :create client command with:
      | f | <%= BushSlicer::HOME %>/testdata/pods/securityContext/pod-selinux.yaml |
    Then the step should succeed
    Given the pod named "selinux-pod" becomes ready
    When I execute on the pod:
      | runcon |
    Then the step should succeed
    And the output should contain:
      | unconfined_u:unconfined_r:svirt_lxc_net_t:s0:c25,c968 |
    When I run the :create client command with:
      | f | <%= BushSlicer::HOME %>/testdata/pods/securityContext/container-selinux.yaml |
    Then the step should succeed
    Given the pod named "selinux-container" becomes ready
    When I execute on the pod:
      | runcon |
    Then the step should succeed
    And the output should contain:
      | unconfined_u:unconfined_r:svirt_lxc_net_t:s0:c25,c968 |
    When I run the :create client command with:
      | f | <%= BushSlicer::HOME %>/testdata/pods/securityContext/both-level.yaml |
    Then the step should succeed
    Given the pod named "both-level-pod" becomes ready
    When I execute on the pod:
      | runcon |
    Then the step should succeed
    And the output should contain:
      | system_u:system_r:svirt_lxc_net_t:s0:c24,c965 |

