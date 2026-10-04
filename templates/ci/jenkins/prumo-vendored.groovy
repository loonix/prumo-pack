// Prumo gates for Jenkins, run from the copy prumo-init vendored into
// .prumo/vendor/. Nothing is downloaded here: a private pack needs no
// credential, and a tag moved upstream cannot change what runs in a build.
//
// prumo-init copies this file to .prumo/vendor/ci/jenkins.groovy and prints
// the snippet to paste into a Jenkinsfile. It never edits Groovy for you:
//
//   stage('Prumo') {
//     steps {
//       script {
//         def prumo = load '.prumo/vendor/ci/jenkins.groovy'
//         prumo.prumoGates()
//       }
//     }
//   }
//
// The vendored verifier runs before every gate: a file that drifted from its
// MANIFEST fails the build before a gate reads it. Rerun prumo-init from the
// pack to upgrade or restore the vendor directory.
//
// There is no catchError here, no unstable() and no softened gate. A check
// that may fail without stopping the build is a log line, not a gate. Deploy
// stages must depend on this one.
//
// Optional environment, with the defaults this file sets:
//   PRUMO_VENDOR_DIR        .prumo/vendor
//   PRUMO_FAIL_CLOSED_DIRS  space separated directories, fail closed, "."
//   PRUMO_ANTI_LEAK         "on" runs the leak gate, anything else skips it
//   PRUMO_ANTI_LEAK_ARGS    space separated arguments for the leak gate, "."
//
// Single quoted payloads mean the shell expands those variables at run time,
// so Groovy interpolates nothing into a command.

def prumoGates() {
  withEnv([
    "PRUMO_VENDOR_DIR=${env.PRUMO_VENDOR_DIR ?: '.prumo/vendor'}",
    "PRUMO_FAIL_CLOSED_DIRS=${env.PRUMO_FAIL_CLOSED_DIRS ?: '.'}",
    "PRUMO_ANTI_LEAK=${env.PRUMO_ANTI_LEAK ?: 'off'}",
    "PRUMO_ANTI_LEAK_ARGS=${env.PRUMO_ANTI_LEAK_ARGS ?: '.'}"
  ]) {
    stage('prumo-vendor-verify') {
      sh '"$PRUMO_VENDOR_DIR/bin/prumo-vendor-verify" "$PRUMO_VENDOR_DIR"'
    }
    stage('prumo-trace') {
      sh '"$PRUMO_VENDOR_DIR/bin/prumo-trace" --root .'
    }
    stage('prumo-fail-closed') {
      // Globbing is off so the directory names are taken literally.
      sh 'set -f; "$PRUMO_VENDOR_DIR/checks/fail-closed.sh" $PRUMO_FAIL_CLOSED_DIRS'
    }
    stage('prumo-metabolic') {
      sh '"$PRUMO_VENDOR_DIR/checks/metabolic.sh" .'
    }
    // Off until the project has its own deny list. On, it is a gate like the
    // others and it stops the build.
    if (env.PRUMO_ANTI_LEAK == 'on') {
      stage('prumo-anti-leak') {
        sh 'set -f; "$PRUMO_VENDOR_DIR/checks/anti-leak.sh" $PRUMO_ANTI_LEAK_ARGS'
      }
    }
  }
}

return this
