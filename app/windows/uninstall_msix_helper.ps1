try {
  $pkg = Get-AppxPackage WGHCWC.LocalChatHelper -ErrorAction SilentlyContinue
  if ($pkg) {
    Remove-AppxPackage $pkg.PackageFullName -ErrorAction Stop
  }
} catch {
  Write-Output $_
}

exit 0
