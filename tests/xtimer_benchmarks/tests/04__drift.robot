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

Force Tags  dev

*** Keywords ***
Measure Drift
    [Documentation]            Run the drift simple benchmark
    [Arguments]                ${duration}
    [Teardown]                 Run Keywords                          PHILIP Reset         API Sync Shell
    FOR                        ${i}                                  IN RANGE             5
    API Call Should Succeed    Drift                                 ${duration}
    Record Property            dut-result-${duration}-repeat-${i}    ${RESULT['data']}

    API Call Should Succeed    PHILIP.Read Trace
    ${PHILIP_RES}=             DutDeviceIf.Filter Trace                 ${RESULT['data']}    select_vals=FALLING    data_keys=diff
    ${RESULT}=                 DutDeviceIf.Compress Result              ${PHILIP_RES}
    Record Property            philip-result-${duration}-repeat-${i}    ${RESULT['diff']}
    PHILIP Reset
    END

*** Test Cases ***
Measure Drift Template
    [Template]  Measure Drift
    # 1000
    # 25000
    # 50000
    # 75000
    # 100000
    # 500000
    1000000
    5000000
    10000000
    15000000
    30000000
    45000000
    60000000
    # 90000000
    # 120000000

