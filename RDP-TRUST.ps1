
$exportPath = Read-Host "Enter the export path for the certificate files (e.g., C:\Certs)"
if (-not (Test-Path -Path $exportPath)) {
    New-Item -ItemType Directory -Path $exportPath | Out-Null
    Write-Host "Created directory: $exportPath" -ForegroundColor Yellow
} else {
    Write-Host "Folder Path Found: $exportPath" -ForegroundColor Green
}

$certificateName = Read-Host "Enter a name for the certificate please make the name unique (e.g., RDP (Computer Name) Publisher)"

#Part 1: Creating and Distributing the Code Signing Certificate

# 1. Declare the Certificate parameters
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=$certificateName" `
    -KeyUsage DigitalSignature `
    -FriendlyName "RDP Signing Certificate" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -NotAfter (Get-Date).AddYears(3)

# 2. Declare the password for the PFX file
$password = ConvertTo-SecureString -String "YourStrongPassword!" -Force -AsPlainText

# 3. Export the public certificate (CER)
Export-Certificate `
    -Cert $cert `
    -FilePath "$exportPath\rdp-signing.cer"

# 4. Export the public certificate with private key (PFX)
Export-PfxCertificate `
    -Cert $cert `
    -FilePath "$exportPath\rdp-signing.pfx" `
    -Password $password

# 5. Import to Trusted Root CA
Import-Certificate `
    -FilePath "$exportPath\rdp-signing.cer" `
    -CertStoreLocation "Cert:\LocalMachine\Root"

# 6. Import to Trusted Publishers
Import-Certificate `
    -FilePath "$exportPath\rdp-signing.cer" `
    -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher"

# 7. Verify the certificate is in place    
Get-ChildItem Cert:\LocalMachine\My | `
    Where-Object { $_.EnhancedKeyUsageList -match "Code Signing" } | `
    Select-Object Subject, Thumbprint, NotAfter

#Example output:
#Subject                                     Thumbprint                               NotAfter
#-------                                     ----------                               --------
#CN=$certificateName, O=Your Organisation...    A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1B2 1/04/2029 12:00:00 AM

#Copy the Thumbprint value — you will need it in the next step. Remove any spaces if present.

#================================================================================================================================================
#================================================================================================================================================
#================================================================================================================================================
#================================================================================================================================================
#================================================================================================================================================

# Part 2: Signing the RDP file

$getThumbprint = Get-ChildItem Cert:\LocalMachine\My | `
    Where-Object { $_.EnhancedKeyUsageList -match "Code Signing" } | 
    `Select-Object Subject, Thumbprint, NotAfter | Where-Object { $_.Subject -like "*$certificateName*" }

$getThumbprint.Thumbprint

# 8. Verify the certificate's EKU includes Code Signing
$thumbprint = $getThumbprint.Thumbprint
$cert = Get-Item "Cert:\LocalMachine\My\$thumbprint"

# 9. Check Enhanced Key Usage includes Code Signing (OID 1.3.6.1.5.5.7.3.3)
$cert.EnhancedKeyUsageList
$objectId = $cert.EnhancedKeyUsageList | Select-Object -ExpandProperty ObjectId
#You should see Code Signing in the output. If the EKU list is empty or only shows other purposes, the certificate is not suitable for signing

if ($objectId -contains "1.3.6.1.5.5.7.3.3") {
    
    Write-Host "Certificate is suitable for code signing." -ForegroundColor Green
} else {
    Write-Host "Certificate does NOT have Code Signing EKU. Please check the certificate." -ForegroundColor Red
    exit
}


# 10. Prompt the user to enter the path to the RDP file they want to sign
$loop = $true

while ($loop) {
    $rdpFilePath = Read-Host "Enter the full path to the RDP file you want to sign (e.g., C:\ChangeMe\YourFile.rdp)"
        if (-not (Test-Path -Path $rdpFilePath)) {
            Write-Host "RDP file not found at: $rdpFilePath" -ForegroundColor Red
            $rdpFilePath
        } else {
            Write-Host "RDP file found at: $rdpFilePath" -ForegroundColor Green
            $loop = $false
        }
}

# 11. Sign the RDP file using the certificate
# Example: rdpsign.exe /sha256 <thumbprint> <path-to-rdp-file>
rdpsign.exe /sha256 $thumbprint $rdpFilePath

Write-Host "RDP file signed successfully with certificate: $certificateName" -ForegroundColor Green

# ****** Distributing the Certificate via Group Policy ******

# Open Group Policy Management Console (gpmc.msc).
# Create or edit a GPO linked to the appropriate OU or domain.
# Navigate to:
# Computer Configuration > Policies > Windows Settings > Security Settings > Public Key Policies > Trusted Publishers
# Right-click Trusted Publishers, select Import, and import your .cer file.
# Repeat for Trusted Root Certification Authorities if using a self-signed certificate.
# Link the GPO and allow it to propagate (or force with gpupdate /force on clients).


# ******* Cleanup: Remove the certificate from the local machine store if needed ******

# $thumbprints = @(
#  "C2091CC3EA178824630CA7A0F2A9FAFF60114C0",
#  "A404ABC2F8C16CBC5D926E3A31236074F8022"
# )

# foreach ($t in $thumbprints) {
#     Remove-Item "Cert:\LocalMachine\My\$t" -Force
# }