import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey
import hudson.util.Secret
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl
import com.cloudbees.plugins.credentials.SecretBytes
import groovy.json.JsonSlurper
import java.util.Base64

/*
  Dynamic Jenkins credential seeder.

  Registry file:
    /var/jenkins_home/jenkins-credentials.json

  Secret values:
    /var/jenkins_home/jenkins-credentials.env is loaded as container env_file by Docker Compose.

  Supported types:
    - secretText
    - usernamePassword
    - sshPrivateKey
    - fileCredential

  Empty values are skipped. Existing credentials with the same ID are replaced, so terraform apply can update credentials.
*/

String envValue(String key) {
  if (key == null || key.trim().isEmpty()) {
    return ''
  }
  def value = System.getenv(key)
  return value == null ? '' : value.trim()
}

String decodeBase64Env(String key) {
  String value = envValue(key)
  if (value.isEmpty()) {
    return ''
  }
  return new String(Base64.getDecoder().decode(value), 'UTF-8')
}

String normalizePrivateKey(String keyValue) {
  if (keyValue == null) {
    return ''
  }
  return keyValue.replace('\\n', '\n').trim()
}

def registryPath = System.getenv('JENKINS_CREDENTIALS_REGISTRY') ?: '/var/jenkins_home/jenkins-credentials.json'
def registryFile = new File(registryPath)
if (!registryFile.exists()) {
  println("Jenkins credential registry not found at ${registryPath}. No dynamic credentials will be seeded.")
  return
}

def parsed = new JsonSlurper().parse(registryFile)
def credentialDefinitions = parsed.credentials ?: []

def provider = SystemCredentialsProvider.getInstance()
def store = provider.getStore()
def domain = Domain.global()

def removeExistingCredential = { String id ->
  def existing = store.getCredentials(domain).find { it.id == id }
  if (existing != null) {
    store.removeCredentials(domain, existing)
    println("Removed existing Jenkins credential '${id}' before update")
  }
}

def addCredential = { String id, credential ->
  removeExistingCredential(id)
  store.addCredentials(domain, credential)
  println("Created/Updated Jenkins credential '${id}'")
}

credentialDefinitions.each { item ->
  String id = (item.id ?: '').trim()
  String type = (item.type ?: '').trim()
  String description = item.description ?: id

  if (id.isEmpty() || type.isEmpty()) {
    println('Skipping credential definition because id or type is empty')
    return
  }

  try {
    switch (type) {
      case 'secretText':
        String secret = envValue(item.secretEnv as String)
        if (secret.isEmpty()) {
          println("Skipping Jenkins credential '${id}' because secretEnv value is empty")
          return
        }
        addCredential(id, new StringCredentialsImpl(
          CredentialsScope.GLOBAL,
          id,
          description,
          Secret.fromString(secret)
        ))
        break

      case 'usernamePassword':
        String username = envValue(item.usernameEnv as String)
        String password = envValue(item.passwordEnv as String)
        if (username.isEmpty() || password.isEmpty()) {
          println("Skipping Jenkins credential '${id}' because username/password env value is empty")
          return
        }
        addCredential(id, new UsernamePasswordCredentialsImpl(
          CredentialsScope.GLOBAL,
          id,
          description,
          username,
          password
        ))
        break

      case 'sshPrivateKey':
        String username = envValue(item.usernameEnv as String)
        String privateKey = ''
        if (item.privateKeyBase64Env) {
          privateKey = decodeBase64Env(item.privateKeyBase64Env as String)
        } else if (item.privateKeyEnv) {
          privateKey = normalizePrivateKey(envValue(item.privateKeyEnv as String))
        }
        String passphrase = envValue(item.passphraseEnv as String)

        if (username.isEmpty() || privateKey.isEmpty()) {
          println("Skipping Jenkins credential '${id}' because SSH username/private key value is empty")
          return
        }

        addCredential(id, new BasicSSHUserPrivateKey(
          CredentialsScope.GLOBAL,
          id,
          username,
          new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(privateKey),
          passphrase.isEmpty() ? null : passphrase,
          description
        ))
        break

      case 'fileCredential':
        String fileName = (item.fileName ?: "${id}.txt").trim()
        String fileContent = ''
        if (item.fileContentBase64Env) {
          fileContent = decodeBase64Env(item.fileContentBase64Env as String)
        } else if (item.fileContentEnv) {
          fileContent = envValue(item.fileContentEnv as String).replace('\\n', '\n')
        }

        if (fileContent.isEmpty()) {
          println("Skipping Jenkins credential '${id}' because file content env value is empty")
          return
        }

        addCredential(id, new FileCredentialsImpl(
          CredentialsScope.GLOBAL,
          id,
          description,
          fileName,
          SecretBytes.fromBytes(fileContent.getBytes('UTF-8'))
        ))
        break

      default:
        println("Skipping Jenkins credential '${id}' because unsupported type '${type}' was configured")
        break
    }
  } catch (Throwable t) {
    println("ERROR while creating/updating Jenkins credential '${id}': ${t.class.name}: ${t.message}")
    throw t
  }
}

provider.save()
println("Jenkins dynamic credentials seeding completed successfully. Processed ${credentialDefinitions.size()} configured credential definitions.")
