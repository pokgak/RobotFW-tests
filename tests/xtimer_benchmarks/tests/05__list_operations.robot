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

Force Tags     dev

*** Keywords ***
List Operations
    [Documentation]            Run the list operations benchmark
    [Arguments]                ${count}
    API Call Should Succeed    Drift        ${count}

    API Call Should Succeed    PHILIP.Read Trace
    ${PHILIP_RES}=             DutDeviceIf.Filter Trace         ${RESULT['data']}    select_vals=FALLING    data_keys=diff
    ${RESULT}=                 DutDeviceIf.Compress Result      ${PHILIP_RES}

    Record Property            count        ${count}
    Record Property            trace        ${RESULT['diff']}

*** Test Cases ***
Measure List Operations
    [Template]  List Operations
    FOR  ${n}  IN RANGE  1  11
        ${n}
    END
