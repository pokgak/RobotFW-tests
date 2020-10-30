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
Test Template  Measure Sleep Jitter

# Force Tags  dev

*** Keywords ***
Measure Sleep Jitter
    [Documentation]            Run the sleep jitter benchmark
    [Arguments]                ${bg_timer_count}
    [Teardown]  Run Keywords  PHILIP Reset

    API Call Should Succeed    Sleep Jitter                     ${bg_timer_count}
    ${RESULT}=                 DutDeviceIf.Compress Result      ${RESULT['data']}
    Record Property            main-timer-interval              ${RESULT['main-timer-interval']}
    Record Property            bg-timer-interval                ${RESULT['bg-timer-interval']}
    Record Property            bg-timer-count                   ${RESULT['bg-timer-count']}
    API Call Should Succeed    PHILIP.Read Trace
    ${FILTERED}=               DutDeviceIf.Filter Trace         trace=${RESULT['data']}    select_vals=FALLING    data_keys=diff
    ${RESULT}=                 DutDeviceIf.Compress Result      ${FILTERED}
    Record Property            trace                            ${RESULT['diff']}

*** Test Cases ***    BG TIMERS
0 BG Timers     0
5 BG Timers     5
10 BG Timers    10
15 BG Timers    15
20 BG Timers    20
25 BG Timers    25
