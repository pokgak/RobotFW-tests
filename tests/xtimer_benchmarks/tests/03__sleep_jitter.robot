*** Settings ***
Library    DutDeviceIf    port=%{PORT}    baudrate=%{BAUD}    timeout=${%{HIL_CMD_TIMEOUT}}    connect_wait=${%{HIL_CONNECT_WAIT}}    parser=json

Resource    api_shell.keywords.txt
Resource    philip.keywords.txt

Suite Setup    Run Keywords
...            RIOT Reset
...            PHILIP Reset
...            API Firmware Data Should Match
Test Setup     Run Keywords
...            PHILIP Reset
...            API Sync Shell
Test Template  Repeat Measure Jitter

Force Tags  dev

*** Keywords ***
Test Teardown
    Run Keyword If  '${KEYWORD_STATUS}' != 'PASS'     RIOT Reset
    PHILIP Reset

Measure Sleep Jitter
    [Documentation]            Run the sleep jitter benchmark
    [Arguments]                ${bg_timer_count}
    [Teardown]                 Test Teardown

    API Call Should Succeed    Sleep Jitter                     ${bg_timer_count}
    ${RESULT}=                 DutDeviceIf.Compress Result      ${RESULT['data']}
    Record Property            main-timer-interval              ${RESULT['main-timer-interval']}
    Record Property            bg-timer-interval                ${RESULT['bg-timer-interval']}
    Record Property            bg-timer-count                   ${RESULT['bg-timer-count']}
    API Call Should Succeed    PHILIP.Read Trace

    ${FILTERED}=               DutDeviceIf.Filter Trace         trace=${RESULT['data']}    select=FALLING
    ${RESULT}=                 DutDeviceIf.Compress Result      ${FILTERED}
    Record Property            trace                            ${RESULT['diff']}

Repeat Measure Jitter
    [Arguments]     ${bg_timer_count}
    [Teardown]      PHILIP Reset
    FOR  ${n}  IN RANGE  1
        Measure Sleep Jitter       ${bg_timer_count}
    END

*** Test Cases ***    BG TIMERS
0 BG Timers     0
5 BG Timers     5
10 BG Timers    10
15 BG Timers    15
20 BG Timers    20
25 BG Timers    25
