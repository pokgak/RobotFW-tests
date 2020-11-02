*** Settings ***
Library    DutDeviceIf    port=%{PORT}    baudrate=%{BAUD}    timeout=${%{HIL_CMD_TIMEOUT}}    connect_wait=${%{HIL_CONNECT_WAIT}}    parser=json

Resource    api_shell.keywords.txt
Resource    philip.keywords.txt
Resource    util.keywords.txt

Suite Setup    Run Keywords
...            RIOT Reset
...            PHILIP Reset
...            API Firmware Data Should Match
Test Setup     Run Keywords
...            PHILIP Reset
...            API Sync Shell

# Force Tags     dev

*** Keywords ***
Measure Timer Overhead
    [Arguments]    ${no}    ${method}    ${position}
    [Teardown]  Run Keywords  PHILIP Reset

    API Call Should Succeed    Overhead Timer                 ${method}                      ${position}
    ${RESULT}=                 Run Keyword                    DutDeviceIf.Compress Result    data=${RESULT['data']}
    Record Property            timer-count                    ${RESULT['timer count']}
    Record Property            sample-count                   ${RESULT['sample count']}
    API Call Should Succeed    PHILIP.Read Trace
    ${RESULT}=                 DutDeviceIf.Filter Trace       trace=${RESULT['data']}        select=FALLING
    ${OVERHEAD}=               DutDeviceIf.Compress Result    ${RESULT}

    Record Property    overhead-${no}-${method}-${position}-timer    ${OVERHEAD['diff']}

Measure Timer Now Overhead
    [Teardown]  Run Keywords  PHILIP Reset

    API Call Should Succeed    Overhead Timer Now
    API Call Should Succeed    PHILIP.Read Trace
    ${RESULT}=                 DutDeviceIf.Filter Trace         trace=${RESULT['data']}    select=FALLING
    ${OVERHEAD}=               DutDeviceIf.Compress Result      ${RESULT}
    Record Property            overhead-01-timer-now            ${OVERHEAD['diff']}

emergency
    fail    GPIO event does not start with RISING

Measure GPIO Overhead
    [Teardown]  Run Keywords  PHILIP Reset

    API Call Should Succeed    Overhead GPIO
    API Call Should Succeed    PHILIP.Read Trace
    ${RESULT}=                 DutDeviceIf.Filter Trace                   trace=${RESULT['data']}     select=FALLING
    ${GPIO_OVERHEAD}=          DutDeviceIf.Compress Result                ${RESULT}
    Record Property            overhead-00-gpio                              ${GPIO_OVERHEAD['diff']}

Set ${count} Timers
    [Documentation]            Run the list operations benchmark
    [Teardown]  Run Keywords  PHILIP Reset

    API Call Should Succeed    DutDeviceIf.List Operation       ${count}
    API Call Should Succeed    PHILIP.Read Trace
    ${PHILIP_RES}=             DutDeviceIf.Filter Trace         ${RESULT['data']}    select=FALLING
    ${RESULT}=                 DutDeviceIf.Compress Result      ${PHILIP_RES}

    Record Property            ${count}-timer-trace             ${RESULT['diff']}

*** Test Cases ***
Measure GPIO
    [Teardown]  Run Keywords  PHILIP Reset
    FOR  ${_}  IN RANGE  20
        Measure GPIO Overhead
    END


# get time
Measure Overhead TIMER_NOW
    [Teardown]  Run Keywords  PHILIP Reset
    FOR  ${_}  IN RANGE  20
        Measure Timer Now Overhead
    END

# set timer
Measure Overhead Set First Timer     Measure Timer Overhead    02    set    first
Measure Overhead Set Middle Timer    Measure Timer Overhead    03    set    middle
Measure Overhead Set Last Timer      Measure Timer Overhead    04    set    last
# # remove timer
Measure Overhead Remove First Timer     Measure Timer Overhead    05    remove    first
Measure Overhead Remove Middle Timer    Measure Timer Overhead    06    remove    middle
Measure Overhead Remove Last Timer      Measure Timer Overhead    07    remove    last

# list operations
Measure Add Timers
    [Teardown]  Run Keywords  PHILIP Reset
    RIOT Reset  # make sure earlier does not affect this
    FOR  ${n}  IN RANGE  1  51
        Set ${n} Timers
    END
