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

# Force Tags  dev

*** Keywords ***
Measure Sleep Accuracy with ${type} for ${duration}
    [Documentation]            Sleep for specified duration in microseconds (us)
    [Teardown]                 Run Keywords                                         PHILIP Reset
    API Call Should Succeed    Sleep Accuracy                                       ${type}                    ${duration}
    API Call Should Succeed    PHILIP.Read Trace
    ${RESULT}=                 DutDeviceIf.Filter Trace                             trace=${RESULT['data']}    select_vals=FALLING    data_keys=diff
    ${ACCURACY}=               DutDeviceIf.Compress Result                          ${RESULT}
    Record Property            accuracy-${type}-${duration}-philip                  ${ACCURACY['diff']}

*** Test Cases ***
Measure TIMER_SET Accuracy
    FOR     ${duration}     IN RANGE    1    101
        Measure Sleep Accuracy with TIMER_SET for ${duration}
    END

Measure TIMER_SLEEP Accuracy
    FOR     ${duration}     IN RANGE    1    101
        Measure Sleep Accuracy with TIMER_SLEEP for ${duration}
    END

