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
    IIS_SITEPATH  = "C:\\inetpub\\labiba\\Site1"
    BACKUP_ROOT   = "C:\\IIS-Backups"
    ARTIFACT_DIR  = "artifact"
    HEALTH_URL    = "http://localhost:8001/index.html"  // check the actual HTML file
    EXPECT_TEXT   = ""                                   // empty = skip body text check
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Prepare Artifact') {
      steps {
        powershell '''
          Write-Host "==> Preparing HTML artifact..."
          $artifact = Join-Path $env:WORKSPACE "${env:ARTIFACT_DIR}"
          if (-not (Test-Path $artifact)) {
            New-Item -ItemType Directory -Path $artifact | Out-Null
          }

          # Copy index.html to artifact folder
          Copy-Item -Path (Join-Path $env:WORKSPACE "index.html") -Destination $artifact -Force

          # Display artifact contents for confirmation
          Write-Host "==> Artifact contents:"
          Get-ChildItem -Path $artifact -Recurse
        '''
        archiveArtifacts artifacts: "${ARTIFACT_DIR}/**", fingerprint: true
      }
    }

    stage('Backup Current Site') {
      steps {
        powershell '''
          Write-Host "==> Running IIS backup..."
          $script = Join-Path $env:WORKSPACE "scripts\\backup.ps1"
          & $script `
            -SiteName "${env:IIS_SITE}" `
            -SitePath "${env:IIS_SITEPATH}" `
            -BackupRoot "${env:BACKUP_ROOT}"
        '''
      }
    }

    stage('Deploy to IIS') {
      steps {
        powershell '''
          Write-Host "==> Starting deployment..."
          $script = Join-Path $env:WORKSPACE "scripts\\deploy.ps1"

          & $script `
            -AppPool  "${env:IIS_APPPOOL}" `
            -SitePath "${env:IIS_SITEPATH}" `
            -BuildDir (Join-Path $env:WORKSPACE "${env:ARTIFACT_DIR}")
        '''
      }
    }

    stage('Health Check') {
      steps {
        powershell '''
          Write-Host "==> Performing health check..."
          $script = Join-Path $env:WORKSPACE "scripts\\test-and-rollback.ps1"
          & $script `
            -Url "${env:HEALTH_URL}" `
            -BackupRoot "${env:BACKUP_ROOT}" `
            -SiteName "${env:IIS_SITE}" `
            -AppPool  "${env:IIS_APPPOOL}" `
            -SitePath "${env:IIS_SITEPATH}" `
            -ExpectedText "${env:EXPECT_TEXT}" `
            -ExpectedStatus 200
        '''
      }
    }
  }

  post {
    success {
      echo '✅ Deployed successfully to Site1 (C:\\inetpub\\labiba\\Site1)!'
    }
    failure {
      echo '❌ Deployment failed. Rollback attempted.'
    }
  }
}
