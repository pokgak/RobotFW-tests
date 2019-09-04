*** Settings ***
Documentation       Verify basic functionality of the Periph Timer API.

# reset application and check DUT has correct firmware, skip all tests on error
Suite Setup         Run Keywords    PHiLIP.DUT Reset
...                                 API Firmware Should Match
# reset application before running any test
Test Setup          Run Keywords    PHiLIP.DUT Reset
...                                 API Sync Shell
Test Teardown       PHiLIP.DUT Reset

# import libs and keywords

Resource            api_shell.keywords.txt
Resource            periph_timer.keywords.txt

# add default tags to all tests
Force Tags          periph_timer

*** Variables ***
${ACCEPTABLE_ERROR_PERCENT}    ${2}
${DEBUG_PORT}                  %{DEBUG0_PORT}
${DEBUG_PIN}                   %{DEBUG0_PIN}

*** Test Cases ***
Small Timer Delays
    [Template]  Timer Init With ${freq} Hz and Set To ${ticks}
    FOR    ${ticks}    IN RANGE  20  0  -1
        1000000  ${ticks}
    END

Timer Frequency Accuracy
    [Template]   Check If Timer At ${freq} Hz Has Less Error Than ${perc} Percent
    FOR    ${freq}    IN RANGE  100  1000  100
        ${freq}  ${ACCEPTABLE_ERROR_PERCENT}
    END
    FOR    ${freq}    IN RANGE  1000  10000  1000
        ${freq}  ${ACCEPTABLE_ERROR_PERCENT}
    END
    FOR    ${freq}    IN RANGE  10000  100000  10000
        ${freq}  ${ACCEPTABLE_ERROR_PERCENT}
    END
    FOR    ${freq}    IN RANGE  100000  1000000  100000
        ${freq}  ${ACCEPTABLE_ERROR_PERCENT}
    END
    FOR    ${freq}    IN RANGE  1000000  10000000  1000000
        ${freq}  ${ACCEPTABLE_ERROR_PERCENT}
    END

Timer Peak To Peak Jitter
    [Documentation]     Measure how much the measured trigger time varies when
    ...                 setting a timer for the same value multiple times
    ${freq}             Set Variable  ${1000000}
    ${ticks}            Set Variable  ${1000}
    ${diffs}            Create List
    ${maxp2pj_perc}     Set Variable  ${2}
    ${maxp2pj}          Evaluate  ${ticks} / 100 * ${maxp2pj_perc} / ${freq}

    # for a representative set of measurements this should be increased to ~100000
    ${run_cnt}          Set Variable  ${100}

    API Call Should Succeed       Timer Init  dev=0  freq=${freq}  cbname=cb_toggle  gpio_port=${DEBUG_PORT}  gpio_pin=${DEBUG_PIN}

    FOR  ${cnt}  IN RANGE  0  ${run_cnt}  1
        Run Keywords              PHiLIP Reset
        Run Keywords              Enable Debug GPIO Trace On Pin 0
        API Call Should Succeed   Timer Set  dev=0  chan=0  ticks=${ticks}  gpio_port=${DEBUG_PORT}  gpio_pin=${DEBUG_PIN}
        API Call Should Succeed   PHiLIP.Read Trace
        ${trace}=                 Set Variable  ${RESULT['data']}
        ${d1}=                    Evaluate  ${trace}[1][time] - ${trace}[0][time]
        Append To List            ${diffs}  ${d1}
    END

    Sort List                     ${diffs}
    ${min}=                       Get From List 	${diffs}  ${0}
    ${max}=                       Get From List 	${diffs}  ${run_cnt - 1}
    ${p2pj}=                      Evaluate  ${max} - ${min}
    Should Be True                ${p2pj} < ${maxp2pj}
