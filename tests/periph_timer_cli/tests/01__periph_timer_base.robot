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
Return Codes
    [Documentation]             Basic checks to see if the return codes are valid
    API Call Should Succeed     Timer Init  freq=%{PERIPH_TIMER_HZ}
    API Call Should Succeed     Timer Set  ticks=${10000}

Timer Values Should Increase
    [Documentation]             Verify timer values are monotonously increasing.
    API Call Should Succeed     Timer Init  freq=%{PERIPH_TIMER_HZ}
    API Call Should Succeed     Timer Read
    ${t1}=                      API Get Last Result As Integer
    API Call Should Succeed     Timer Read
    ${t2}=                      API Get Last Result As Integer
    Should Be True              ${t2} > ${t1}

Timer Read Overhead
    [Documentation]           Measure how long a timer_read call takes. For now
    ...                       this is only used as benchmark without constraints
    Run Keywords              Enable Debug GPIO Trace On Pin 0
    ${repeat_cnt}             Set Variable  ${1000000}
    API Call Should Succeed   Timer Init  freq=%{PERIPH_TIMER_HZ}  cbname=cb_toggle  gpio_port=${DEBUG_PORT}  gpio_pin=${DEBUG_PIN}
    API Call Should Succeed   Timer Read Bench  repeat_cnt=${repeat_cnt}  gpio_port=${DEBUG_PORT}  gpio_pin=${DEBUG_PIN}
    API Call Should Succeed   PHiLIP.Read Trace
    ${trace}=                 Set Variable  ${RESULT['data']}
    ${us_per_read}=           Evaluate  (${trace}[1][time] - ${trace}[0][time]) * 1000000 / ${repeat_cnt}
