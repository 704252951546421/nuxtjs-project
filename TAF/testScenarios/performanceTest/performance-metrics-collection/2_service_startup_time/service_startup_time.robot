*** Settings ***
Documentation   Measure the startup time for starting all services at once
...             Get service start up time with creating containers
...             Get service start up time without creating containers
Library         Process
Library         TAF/testCaseModules/keywords/setup/edgex.py
Library         TAF/testCaseModules/keywords/performance-metrics-collection/ServiceStartupTime.py
Library         TAF/testCaseModules/keywords/performance-metrics-collection/StartupTimeHandler.py
Library         TAF/testCaseModules/keywords/setup/startup_checker.py
Resource        TAF/testCaseModules/keywords/common/commonKeywords.robot
Suite Setup     Setup Suite

*** Variables ***
${SUITE}          Measure services startup time and get max, min, and average
${LOG_FILE_PATH}  ${WORK_DIR}/TAF/testArtifacts/logs/performance-metric-services-startup-time.log
${clear_mem_cache}   sync; echo 3 | tee /proc/sys/vm/drop_caches

*** Test Cases ***
StartupTime001 - Get service startup time with creating containers
    ${services_startup_time_list}=  Deploy edgex with creating containers and get startup time
    ${service_aggregations}=  Get startup time and add to dictionary  ${services_startup_time_list}
    show full startup time report  Full startup time with creating containers  ${services_startup_time_list}
    show startup time with avg max min  Startup time aggregations with creating containers  ${service_aggregations}
    set global variable  ${startup_time_with_create_container}  ${service_aggregations}
    [Teardown]  run keyword if test failed  set global variable  ${startup_time_with_create_container}  None

StartupTime002 - Get service startup time without creating containers
    [Setup]  Run keywords   Deploy EdgeX  -  PerformanceMetrics
             ...            AND  Stop services
    ${services_startup_time_list}=  Deploy edgex without creating containers and get startup time
    ${service_aggregations}=  Get startup time and add to dictionary  ${services_startup_time_list}
    show full startup time report  Full startup time without creating containers  ${services_startup_time_list}
    show startup time with avg max min  Startup time aggregations without creating containers  ${service_aggregations}
    set global variable  ${startup_time_without_create_container}  ${service_aggregations}
    [Teardown]  Run Keywords  Shutdown services
                ...           AND  run keyword if test failed  set global variable  ${startup_time_without_create_container}  None


*** Keywords ***
Deploy edgex with creating containers and get startup time
    @{total_startup_time_list}=  Create List
    @{service_startup_time_list}=  Create List
    FOR  ${index}    IN RANGE  0  ${STARTUP_TIME_LOOP_TIME}
        ${result}=  Run Process  ${clear_mem_cache}  shell=True
                    ...          stdout=${WORK_DIR}/TAF/testArtifacts/logs/clear_mem.log
        Start time is recorded
        Deploy EdgeX  -  PerformanceMetrics
        ${services_startup_time}=  fetch services startup time
        Shutdown services
        Append to list  ${service_startup_time_list}  ${services_startup_time}
        Check service is stopped or not
    END
    log  ${service_startup_time_list}
    [Return]  ${service_startup_time_list}

Deploy edgex without creating containers and get startup time
    @{service_startup_time_list}=  Create List
    FOR  ${index}    IN RANGE  0  ${STARTUP_TIME_LOOP_TIME}
        ${result}=  Run Process  ${clear_mem_cache}  shell=True
                    ...          stdout=${WORK_DIR}/TAF/testArtifacts/logs/clear_mem_cache.log
        Start time is recorded
        Deploy EdgeX  -  PerformanceMetrics
        ${services_startup_time}=  fetch services startup time without creating containers
        Stop services
        Append to list  ${service_startup_time_list}  ${services_startup_time}
        Check service is stopped or not
    END
    log  ${service_startup_time_list}
    [Return]  ${service_startup_time_list}

Get startup time and add to dictionary
    [Arguments]  ${services_startup_time}
    @{service_keys}=  Get Dictionary Keys  ${services_startup_time}[0]  sort_keys=False
    @{service_aggregation_list}=    create list
    FOR  ${service}  IN  @{service_keys}
        ${service_binary_list}=    Get service startup time list  ${services_startup_time}  ${service}  binaryStartupTime
        ${service_container_list}=    Get service startup time list  ${services_startup_time}  ${service}  startupTime
        startup time is less than threshold setting  ${service_binary_list}
        startup time is less than threshold setting  ${service_container_list}
        ${binary_aggregations}=  Get avg max min values  ${service_binary_list}
        ${container_aggregations}=  Get avg max min values  ${service_container_list}
        ${aggregation_value}=  create dictionary  binaryStartupTime=${binary_aggregations}  startupTime=${container_aggregations}
        ${service_aggregations}=  create dictionary  ${service}=${aggregation_value}
        APPEND TO LIST  ${service_aggregation_list}  ${service_aggregations}
    END
    [Return]  ${service_aggregation_list}

Get service startup time list
    [Arguments]  ${services_startup_time}  ${service}  ${startup_key}
    @{service_data_list}=    create list
    FOR  ${index}  IN RANGE  0  ${STARTUP_TIME_LOOP_TIME}
        log  ${services_startup_time}[${index}]
        ${service_data}=  Get from dictionary  ${services_startup_time}[${index}]  ${service}
        ${startup_value_str}=  Get from dictionary  ${service_data}  ${startup_key}
        ${startup_value}=  run keyword if  '${startup_key}' == 'startupTime'  convert to number  ${startup_value_str}
                           ...    ELSE IF  '${startup_key}' == 'binaryStartupTime' and '${service}' == 'Total startup time'
                           ...             Evaluate  0
                           ...    ELSE     Convert milliseconds to seconds  ${startup_value_str}
        append to list  ${service_data_list}  ${startup_value}
    END
    [Return]  ${service_data_list}

Convert milliseconds to seconds
    [Arguments]  ${time}
    ${check_time_ms}=  Run Keyword And Return Status  Should Match Regexp  ${time}  \d*.\d*ms
    ${check_time_µs}=  Run Keyword And Return Status  Should Match Regexp  ${time}  \d*.\d*µs
    ${time_str}=   Remove string  ${time}  µ  m  s
    ${time_num}=   convert to number  ${time_str}
    ${startup_value}=  run keyword if  ${check_time_ms} == True  EVALUATE  ${time_num} / 1000
                       ...    ELSE IF  ${check_time_µs} == True  EVALUATE  ${time_num} / 1000000
                       ...    ELSE     SET VARIABLE  ${time_num}
    [Return]  ${startup_value}
