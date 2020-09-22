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
Test Template    Measure Sleep Jitter

# Force Tags  dev

*** Keywords ***
Measure Sleep Jitter
    [Documentation]            Run the sleep jitter benchmark
    [Arguments]                ${bg_timers}                      ${divisor}=1
    API Call Should Succeed    Sleep Jitter                      ${bg_timers}                   ${divisor}
    ${RESULT}=                 DutDeviceIf.Compress Result       ${RESULT['data']}
    ${interval}=               Evaluate                          $RESULT.get('interval', [])
    Record Property            intervals                         ${interval}
    Record Property            divisor                           ${divisor}

    API Call Should Succeed    PHILIP.Read Trace
    ${FILTERED}=               DutDeviceIf.Filter Trace       trace=${RESULT['data']}    select_vals=FALLING    data_keys=diff
    ${RESULT}=                 DutDeviceIf.Compress Result    ${FILTERED}
    Record Property            trace                          ${RESULT['diff']}

*** Test Cases ***    BG TIMERS
0 BG Timer            0
25 BG Timers          25
50 BG Timers          50
75 BG Timers          75
100 BG Timers         100




