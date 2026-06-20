import jenkins.model.*
import hudson.security.*
import hudson.model.User

/*
  Jenkins admin/security bootstrap.

  Purpose:
  - Create admin user if it does not exist
  - Update admin password if user already exists
  - Apply security realm and authorization strategy
  - Works even when Jenkins is redeployed with existing jenkins_home volume

  Required env values:
  - JENKINS_ADMIN_USER
  - JENKINS_ADMIN_PASSWORD
*/

def instance = Jenkins.get()

String adminUser = System.getenv("JENKINS_ADMIN_USER") ?: "admin"
String adminPassword = System.getenv("JENKINS_ADMIN_PASSWORD") ?: ""

if (adminPassword == null || adminPassword.trim().isEmpty()) {
    println("JENKINS_ADMIN_PASSWORD is empty. Skipping Jenkins admin setup.")
    return
}

def realm = instance.getSecurityRealm()

if (!(realm instanceof HudsonPrivateSecurityRealm)) {
    realm = new HudsonPrivateSecurityRealm(false)
    instance.setSecurityRealm(realm)
    println("Configured Jenkins private security realm.")
}

def existingUser = User.getById(adminUser, false)

if (existingUser == null) {
    realm.createAccount(adminUser, adminPassword)
    println("Created Jenkins admin user: ${adminUser}")
} else {
    existingUser.addProperty(HudsonPrivateSecurityRealm.Details.fromPlainPassword(adminPassword))
    existingUser.save()
    println("Updated Jenkins admin password for user: ${adminUser}")
}

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()

println("Jenkins admin/security setup completed successfully.")
