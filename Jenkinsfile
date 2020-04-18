def nodes = nodesByLabel('HIL')
def boards = []
def tests = []

def triggers = []

if ("${env.BRANCH_NAME}" == 'nightly') {
    // build master with latest RIOT daily at 1:00 AM
    triggers << parameterizedCron('0 1 * * * % HIL_RIOT_VERSION=master')
}

properties([
  parameters([
        choice(name: 'HIL_RIOT_VERSION', choices: ['submodule', 'master', 'pull'], description: 'The RIOT branch or PR to test.'),
        string(name: 'HIL_RIOT_PULL', defaultValue: '0', description: 'RIOT pull request number')
   ]),
   pipelineTriggers(triggers)
])

def stepClone()
{
    deleteDir()
    checkout scm
    // update nightly branch to latest master
    if ("${env.BRANCH_NAME}" == 'nightly') {
        // update nightly branch to master
        sh 'git pull --rebase origin master'
    }
    if ("${env.BRANCH_NAME}" == 'nightly') {
        // update nightly branch to latest master and push
        withCredentials([usernamePassword(credentialsId: 'da54a500-472f-4005-9399-a0ab5ce4da7e', passwordVariable: 'GIT_PASSWORD', usernameVariable: 'GIT_USERNAME')]) {
            sh("""
                git config --global credential.username ${GIT_USERNAME}
                git config --global credential.helper "!echo password=${GIT_PASSWORD}; echo"
                git pull --rebase origin master
                git push origin HEAD:nightly
            """)
        }
    }
    if ("${params.HIL_RIOT_VERSION}" == 'master') {
        // checkout latest RIOT master
        sh 'git submodule update --init --remote --rebase --depth 1'
    }
    else {
        sh 'git submodule update --init --depth 1'
        if ("${params.HIL_RIOT_VERSION}" == 'pull' && "${params.HIL_RIOT_PULL}" != '0') {
            // checkout specified PR number
            def prnum = params.HIL_RIOT_PULL.toInteger()
            sh """
                cd RIOT
                git fetch origin +refs/pull/${prnum}/merge
                git checkout FETCH_HEAD
            """
        }
    }
}

def stepPrintEnv(board, test)
{
    sh 'dist/tools/ci/print_environment.sh'
}

def stepReset(board, test)
{
    sh "python3 -m bph_pal --philip_reset"
    sh "make -C ${test} reset"
}

def stepFlash(board, test)
{
    catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
        sh "make -C ${test} flash"
    }
}

def stepTests(board, test)
{
    def test_name = test.replaceAll('/', '_')
    sh "make -C ${test} robot-clean || true"
    catchError(buildResult: 'UNSTABLE', stageResult: 'SUCCESS') {
        sh "make -C ${test} robot-test"
    }
    sh "make -C ${test} robot-html || true"

    archiveArtifacts artifacts: "build/robot/${board}/${test_name}/*.xml"
    archiveArtifacts artifacts: "build/robot/${board}/${test_name}/*.html"
    junit "build/robot/${board}/${test_name}/xunit.xml"
}

// function to return steps per board
def parallelSteps (board, test) {
    return {
        node (board) {
            catchError() {
                unstash name: 'sources'
//                stepClone()
                stepPrintEnv(board, test)
                stepReset(board, test)
                stepFlash(board, test)
                stepTests(board, test)
            }
        }
    }
}

// detect connected boards and available tests
stage ("setup") {
    node ("master") {
//        checkout scm
        stepClone()
        stash name: 'sources'
        // discover test applications
        tests = sh(returnStdout: true,
                   script:  """
                                for dir in \$(find tests -maxdepth 1 -mindepth 1 -type d); do
                                    [ -d \$dir/tests ] && { echo \$dir ; } || true
                                done
                            """).tokenize()
        echo "run TESTS: " + tests.join(",")
        // discover available boards
        for (int i=0; i<nodes.size(); ++i) {
            def nodeName = nodes[i];
            node (nodeName) {
                boards.push(env.BOARD)
            }
        }
        boards.unique()
        echo "use BOARDS: " + boards.join(",")
    }
}

// create a stage per test with one step per board
for(int i=0; i < tests.size(); i++) {
    test = tests[i].trim()
    stage(test) {
        parallel (
            boards.collectEntries {
                ["${it}" : parallelSteps(it, test)]
            }
        )
    }
}

stage('Notify') {
    node("master") {
        def jobName = currentBuild.fullDisplayName
        emailext (
            body: '''${SCRIPT, template="groovy-html.template"}''',
            mimeType: 'text/html',
            subject: "${jobName}",
            from: 'jenkins@riot-ci.inet.haw-hamburg.de',
            to: '${DEFAULT_RECIPIENTS}',
            replyTo: '${DEFAULT_RECIPIENTS}'
        )
    }
}
