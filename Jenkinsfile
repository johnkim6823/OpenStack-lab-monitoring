// monitor 설정 배포 파이프라인: 준비 → 검증 → 사전 적용 → 배포 → 사후 확인, 실패 시 자동 롤백
pipeline {
  agent any
  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 20, unit: 'MINUTES')
  }
  triggers { pollSCM('H/2 * * * *') }
  environment {
    REMOTE = 'ssh -o StrictHostKeyChecking=accept-new ubuntu@monitor-host'
  }
  stages {
    stage('준비') {
      steps { sshagent(['monitor-ssh']) { sh '$REMOTE "bash -s -- prepare $GIT_COMMIT" < ci/pipeline.sh' } }
    }
    stage('검증') {
      steps { sshagent(['monitor-ssh']) { sh '$REMOTE "bash -s -- validate" < ci/pipeline.sh' } }
    }
    stage('사전 적용') {
      steps { sshagent(['monitor-ssh']) { sh '$REMOTE "bash -s -- canary" < ci/pipeline.sh' } }
    }
    stage('배포') {
      steps {
        script { env.DEPLOYED = 'true' }
        sshagent(['monitor-ssh']) { sh '$REMOTE "bash -s -- deploy $GIT_COMMIT" < ci/pipeline.sh' }
      }
    }
    stage('사후 확인') {
      steps { sshagent(['monitor-ssh']) { sh '$REMOTE "bash -s -- verify" < ci/pipeline.sh' } }
    }
  }
  post {
    failure {
      script {
        if (env.DEPLOYED == 'true') {
          sshagent(['monitor-ssh']) { sh '$REMOTE "bash -s -- rollback" < ci/pipeline.sh' }
        }
      }
    }
    always {
      sshagent(['monitor-ssh']) { sh '$REMOTE "bash -s -- cleanup" < ci/pipeline.sh || true' }
    }
  }
}
