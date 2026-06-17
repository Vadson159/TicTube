# This script extracts the SHA-1 certificate fingerprint from the default Android debug keystore.
# You will need this SHA-1 to set up Google Sign-In in the Google Cloud Console.

$keystore = "$env:USERPROFILE\.android\debug.keystore"
$password = "android"

if (Test-Path $keystore) {
    Write-Host "Extracting SHA-1 from $keystore..."
    keytool -list -v -keystore $keystore -alias androiddebugkey -storepass $password -keypass $password | Select-String "SHA1:"
} else {
    Write-Host "Debug keystore not found at $keystore"
    Write-Host "Please build your app once via Android Studio to generate it."
}
