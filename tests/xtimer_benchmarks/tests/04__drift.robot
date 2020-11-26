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

Force Tags     long

*** Keywords ***
Measure Drift
    [Documentation]            Run the drift simple benchmark
    [Teardown]     Run Keywords  PHILIP Reset
    [Arguments]                ${duration}

    API Call Should Succeed    Drift                                 ${duration}
    Record Property            dut-result-${duration}-repeat    ${RESULT['data']}

    API Call Should Succeed    PHILIP.Read Trace
    ${PHILIP_RES}=             DutDeviceIf.Filter Trace                 ${RESULT['data']}    select=FALLING
    ${RESULT}=                 DutDeviceIf.Compress Result              ${PHILIP_RES}
    Record Property            philip-result-${duration}-repeat    ${RESULT['diff']}

*** Test Cases ***
Measure Drift Template
    [Teardown]  Run Keywords  PHILIP Reset
    [Template]  Measure Drift
    1000000
    10000000
    20000000
    30000000
    40000000
    50000000
    59000000
