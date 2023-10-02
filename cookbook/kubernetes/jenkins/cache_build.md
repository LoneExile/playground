# jenkins with kubernetes

## cache build

- groovy script

```groovy
def MOUNT_PATH = "/home/jenkins/agent/$JOB_NAME/cache/"

podTemplate(
        containers: [
        containerTemplate(
            name: 'nodejs',
            image: 'node:18.18.0',
            command: 'cat',
            ttyEnabled: true
            // command: 'sleep',
            // args: '99d'
            )
        ],
        volumes: [
        persistentVolumeClaim(
            mountPath: MOUNT_PATH,
            claimName: 'cache-repo-storage',
            readOnly: false
            )
        ]
)

{
    node(POD_LABEL) {
        stage('Check node version') {
            container('nodejs') {
                sh 'node -v'
            }
        }

        stage('Echo Mount Path') {
            script {
                echo "MOUNT_PATH_ENV: $MOUNT_PATH"
            }
        }

        stage('Check env branch') {
            sh 'echo $BRANCH_NAME'
        }

        stage('Checkout') {
            container('nodejs') {
              checkout scm
            }
        }

        stage('Restore Cache') {
            // sh 'cp -r $MOUNT_PATH/node_modules . || echo "No cache found"'
            container('nodejs') {
                script {
                    try {
                        sh "cp -r $MOUNT_PATH'node_modules' ."
              } catch (err) {
                        echo 'No cache found'
                    }
                }
            }
        }

        stage('Check npm version') {
            container('nodejs') {
                sh 'npm -v'
            }
        }

        stage('Check branch') {
            sh 'git status'
        }

        stage('Run ls -al') {
            sh 'ls -al'
        }

        stage('install package') {
            container('nodejs') {
                sh 'npm install'
                sh 'pwd'
            }
        }

        stage('Save Cache') {
            container('nodejs') {
                script {
                    sh "mkdir -p $MOUNT_PATH"
                    sh "rm -rf $MOUNT_PATH'node_modules'"
                    sh "cp -r node_modules $MOUNT_PATH"
                }
            }
        }
    }
}
```

- yaml template

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cache-repo-storage 
  namespace: jenkins
spec:
  storageClassName: rook-cephfs
  accessModes:
    # - ReadWriteOnce
    - ReadWriteMany
  resources:
    requests:
      storage: 50Gi
```
