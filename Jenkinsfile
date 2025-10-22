pipeline {
  agent { label 'Windows-actions' }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  triggers {
    githubPush()
  }

  environment {
    IIS_SITE      = "Site1"
    IIS_APPPOOL   = "Site1Pool"
    IIS_SITEPATH  = "\\\\GITHUB-ACTION\\Site1"
    BACKUP_ROOT   = "\\\\GITHUB-ACTION\\IIS-Backup"
    ARTIFACT_DIR  = "artifact"
    HEALTH_URL    = "http://localhost/"
    EXPECT_TEXT   = "Hello Abdullah"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Prepare Artifact') {
      steps {
        pwsh '''
          New-Item -Path "${env:ARTIFACT_DIR}" -ItemType Directory -Force | Out-Null
          Copy-Item -Path "index.html" -Destination "${env:ARTIFACT_DIR}" -Force
        '''
        archiveArtifacts artifacts: "${ARTIFACT_DIR}/**", fingerprint: true
      }
    }

    stage('Backup Current Site') {
      steps {
        pwsh '''
          & "${PWD}\\scripts\\backup.ps1" `
            -SiteName "${env:IIS_SITE}" `
            -SitePath "${env:IIS_SITEPATH}" `
            -BackupRoot "${env:BACKUP_ROOT}"
        '''
      }
    }

    stage('Deploy to IIS') {
      steps {
        pwsh '''
          & "${PWD}\\scripts\\deploy.ps1" `
            -SiteName "${env:IIS_SITE}" `
            -AppPool  "${env:IIS_APPPOOL}" `
            -SitePath "${env:IIS_SITEPATH}" `
            -BuildDir "${PWD}\\${env:ARTIFACT_DIR}"
        '''
      }
    }

    stage('Health Check') {
      steps {
        pwsh '''
          & "${PWD}\\scripts\\test-and-rollback.ps1" `
            -Url "${env:HEALTH_URL}" `
            -BackupRoot "${env:BACKUP_ROOT}" `
            -SiteName "${env:IIS_SITE}" `
            -AppPool  "${env:IIS_APPPOOL}" `
            -SitePath "${env:IIS_SITEPATH}" `
            -ExpectedText "${env:EXPECT_TEXT}"
        '''
      }
    }
  }

  post {
    success {
      echo '✅ Deployed successfully to Site1!'
    }
    failure {
      echo '❌ Deployment failed. Rollback attempted.'
    }
  }
}
