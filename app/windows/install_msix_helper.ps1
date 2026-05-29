try {
  if (Test-Path ".\localsend_msix_helper.msix") {
    Add-AppxPackage .\localsend_msix_helper.msix -ExternalLocation $(Get-Location) -ErrorAction Stop
  }
} catch {
  Write-Output $_
}

exit 0
