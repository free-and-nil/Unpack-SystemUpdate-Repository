<#
Copyright (c) 2024 Olaf Hess
All rights reserved.

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
#>

#REQUIRES -version 2.0

# https://stackoverflow.com/questions/2157554/how-to-handle-command-line-arguments-in-powershell
param (
	[Parameter(Mandatory=$true)][string]$ParamRepositoryFolder,
	[Parameter(Mandatory=$true)][string]$ParamTargetFolder
) #param

if ($Host.Name -ne "ConsoleHost")
{
	# Führt sonst zu Skript-Abbrüchen, wenn Umgebungsvariablen nicht sauber
	# definiert sind (z.B. "LIB contains invalid path")
	Set-StrictMode -Version 3.0
} #if

Clear-Host

function Main
{
	if (-not (CheckParams))
		{ exit 255 }
		
	if (-not (IsRunningWithFullAdminPrivilege))
	{
		Write-Host "This script must be executed with full admin rights"
		exit (0xFE)
	} #if
		
	GetRepositorySubFolders
} #Main

function CheckForInstallationFile ([string]$sSourceFolder, `
								   [string]$sExtractCmd, `
								   [ref]$sSetupExe)
{
	$ExtractTokens = $sExtractCmd.Split(" ")
	
	if ($ExtractTokens -eq $null)
	{
		Write-Host "Error splitting the `"ExtractCommand`" `"$sExtractCmd`""
		return false
	} #if

	$sExecutable = $ExtractTokens[0]
	$sFullPath = $sSourceFolder + "\" + $ExtractTokens[0]
	
	if (Test-Path -Path $sFullPath -PathType Leaf)
	{
		Write-Host "Setup program `"$sExecutable`" found"
		$sSetupExe.Value = [string]$ExtractTokens[0]
		return $true
	} #if
	else
	{
		Write-Host "Setup program `"$sExecutable`" not found -> " `
				   "ignoring folder"
		return $false
	} #if
} #CheckForInstallationFile

function CheckParams
{
	if (Test-Path -Path $ParamRepositoryFolder -PathType Container)
	{ 
		if (Test-Path -Path $ParamTargetFolder -PathType Container)
		{
			do {
				Write-Host "The output folder `"$ParamTargetFolder`" exists. Continue (y/n)?"
			    $Answer = Read-Host "Y / N"
			} until ('y', 'n' -contains $Answer)
			
			# https://blog.ivankahl.com/case-sensitive-and-insensitive-string-comparisons-in-powershell/
			if ($Answer -like "y")
				{ return $true }
			else { return $false }
		} #if 
		
		return $true 
	}
	else 
	{
		Write-Host "Error: Source folder `"$sFolder`" not found"
		return $false
	} #else
} #CheckParams

function CheckValue
{
param([Parameter(Mandatory)][string]$Value,
	  [Parameter(Mandatory)][string]$Desciption)
  
  	if ([string]::IsNullOrEmpty($Value))
	{
		Write-Host "Error: the value `"$Desciption`" is undefined"
		return $false
	} #if
	else { return $true }
} #CheckValue

function CreateFolder ([Parameter(Mandatory)][string]$sPath)
{
	try
	{ 
		New-Item -Path $sPath -ItemType Directory -Force 
		return $true
	} #try
	catch
	{ 
		$_ 
		return $false
	} #catch
} #CreateFolder

function ExtractSetupFiles([string]$sFolder, [string]$sExtractCmd, `
						   [string]$sXmlFile, [string]$sDesc)
						   
{ 
	function GetTargetFolder
	{
		if ($sDesc.ToLower().Contains("chipset"))
			{ return ("!_" + $sFolder) }
		elseif (($sDesc.Contains("Hotkey Features Integration Package")) -or
				($sDesc.Contains("ThinkPad Monitor File")))
			{ return ("~_" + $sFolder) }
		else { return $sFolder }
	} #GetTargetFolder
						   
<# ExtractSetupFiles #>
	[string]$sSetupExe = ""
	[string]$sSourceFolder = $ParamRepositoryFolder + "\" + $sFolder
	
	if (-not (CheckForInstallationFile $sSourceFolder $sExtractCmd `
									   ([ref]$sSetupExe)))
		{ return $false }
	
	[string]$sTargetFolder = $ParamTargetFolder + "\" + (GetTargetFolder)
	
	if (Test-Path -LiteralPath $sTargetFolder -PathType Container)
	{
		Write-Host "The target folder `"$sTargetFolder`" already exists -> ignoring folder"
		return $false
	} #if
	
	if ($sExtractCmd -like "*%PACKAGEPATH%*")
		{  $sExtractCmd = $sExtractCmd.Replace("%PACKAGEPATH%", $sTargetFolder) }
	
	if (CreateFolder $sTargetFolder)
	{
		Copy-Item $sXmlFile -Destination $sTargetFolder -Force
		
		$sParams = $sExtractCmd.SubString($sSetupExe.Length + 1)
		
		Write-Host "Executing file `"$sSetupExe`" ..."
		Start-Process -FilePath ($sSourceFolder + "\" + $sSetupExe) -Wait `
					  -ArgumentList $sParams
							
		# Write-Host "ErrorLevel = $LASTEXITCODE"

		Add-Content -Path ($ParamTargetFolder + "\System_Update.txt") `
					-Value ("$sDesc`t$sFolder")
		
		return $true
	} #if
	
	return $false
} #ExtractSetupFiles

function GetRepositorySubFolders
{
	[int]$iFolderCount = 0
	[int]$iProcessed = 0
	
	foreach ($Item in Get-ChildItem -Path $ParamRepositoryFolder -Force)
	{
		if ($Item.PSIsContainer)
		{ 
			$iFolderCount++
			
			if (ProcessFolder $Item)
				{ $iProcessed++ }
		} #if 
	} #foreach
	
	Write-Host
	Write-Host "Folders found: $iFolderCount; processed: $iProcessed"
} #GetRepositorySubFolder

function IsRunningWithFullAdminPrivilege
{
	$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
	[bool]$IsAdminRole = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	return $IsAdminRole
} #function IsRunningWithFullAdminPrivilege

function Process_XML ([string]$sFolder, [string]$sXmlFile, [ref]$sDesc, `
					  [ref]$sExtractCmd)
<#
                '1' : FPackageType := ptApplication;
                '2' : FPackageType := ptDriver;
                '3' : FPackageType := ptSystemBios;
                '4' : FPackageType := ptFirmware;
#>
{
	function CheckPackageType ([int]$iPackageType)
	{
		if ($iPackageType -eq 3)
		{
			Write-Host "Skipping BIOS update package"
			return $false
		} #if
		elseif ($iPackageType -eq 4)
		{
			Write-Host "Skipping firmware update package"
			return $false
		} #if
		elseif ($iPackageType -ge 5)
		{
			Write-Host "Unknown package type $iPackageType -> skipping package"
			return $false
		} #if
		
		return $true
	} #CheckPackageType
	
<# function Process_XML #>
	[xml]$XmlData = Get-Content $sXmlFile
	
	[string]$sDescription = $XmlData.Package.Title.Desc.'#text'
	[string]$sExtractCommand = $XmlData.Package.ExtractCommand
	
	if (-not ((CheckValue $sDescription "Description") -and `
	    	  (CheckValue $sExtractCommand "ExtractCommand")))
		{ return $false }
		
	Write-Host "Description = $sDescription"
	
	[int]$iPackageType = $XmlData.Package.PackageType.type
	
	if (-not (CheckPackageType $iPackageType))
		{ return $false }
	
	$sDesc.Value = $sDescription
	$sExtractCmd.Value = $sExtractCommand
	
	return $true
} #Process_XML

function ProcessFolder ([string]$sFolder)
{
	Write-Host
	Write-Host "Folder = `"$sFolder`""

	[string]$sFileName = $sFolder + "_2_.xml"
	[string]$sFullName = $ParamRepositoryFolder + "\" + $sFolder + "\" + $sFileName
	
	if (Test-Path -LiteralPath $sFullName -PathType Leaf)
	{
		Write-Host "File = $sFullName"
	
		[string]$sExtractCmd = ""
		[string]$sDescription = ""
	
		if (Process_XML $sFolder $sFullName ([ref]$sDescription) `
						([ref]$sExtractCmd))
		{
			if (ExtractSetupFiles $sFolder $sExtractCmd $sFullName $sDescription)
				{ return $true }
		} #if
	} #if
	else { Write-Host "The folder `"$sFullName`" contains no matching XML file" }
	
	return $false
} #ProcessFolder

. Main

# SIG # Begin signature block
# MIIrkgYJKoZIhvcNAQcCoIIrgzCCK38CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUIQI61DKww3VklZDPoD++gT43
# eQ2ggiTOMIIFbzCCBFegAwIBAgIQSPyTtGBVlI02p8mKidaUFjANBgkqhkiG9w0B
# AQwFADB7MQswCQYDVQQGEwJHQjEbMBkGA1UECAwSR3JlYXRlciBNYW5jaGVzdGVy
# MRAwDgYDVQQHDAdTYWxmb3JkMRowGAYDVQQKDBFDb21vZG8gQ0EgTGltaXRlZDEh
# MB8GA1UEAwwYQUFBIENlcnRpZmljYXRlIFNlcnZpY2VzMB4XDTIxMDUyNTAwMDAw
# MFoXDTI4MTIzMTIzNTk1OVowVjELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3Rp
# Z28gTGltaXRlZDEtMCsGA1UEAxMkU2VjdGlnbyBQdWJsaWMgQ29kZSBTaWduaW5n
# IFJvb3QgUjQ2MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAjeeUEiIE
# JHQu/xYjApKKtq42haxH1CORKz7cfeIxoFFvrISR41KKteKW3tCHYySJiv/vEpM7
# fbu2ir29BX8nm2tl06UMabG8STma8W1uquSggyfamg0rUOlLW7O4ZDakfko9qXGr
# YbNzszwLDO/bM1flvjQ345cbXf0fEj2CA3bm+z9m0pQxafptszSswXp43JJQ8mTH
# qi0Eq8Nq6uAvp6fcbtfo/9ohq0C/ue4NnsbZnpnvxt4fqQx2sycgoda6/YDnAdLv
# 64IplXCN/7sVz/7RDzaiLk8ykHRGa0c1E3cFM09jLrgt4b9lpwRrGNhx+swI8m2J
# mRCxrds+LOSqGLDGBwF1Z95t6WNjHjZ/aYm+qkU+blpfj6Fby50whjDoA7NAxg0P
# OM1nqFOI+rgwZfpvx+cdsYN0aT6sxGg7seZnM5q2COCABUhA7vaCZEao9XOwBpXy
# bGWfv1VbHJxXGsd4RnxwqpQbghesh+m2yQ6BHEDWFhcp/FycGCvqRfXvvdVnTyhe
# Be6QTHrnxvTQ/PrNPjJGEyA2igTqt6oHRpwNkzoJZplYXCmjuQymMDg80EY2NXyc
# uu7D1fkKdvp+BRtAypI16dV60bV/AK6pkKrFfwGcELEW/MxuGNxvYv6mUKe4e7id
# FT/+IAx1yCJaE5UZkADpGtXChvHjjuxf9OUCAwEAAaOCARIwggEOMB8GA1UdIwQY
# MBaAFKARCiM+lvEH7OKvKe+CpX/QMKS0MB0GA1UdDgQWBBQy65Ka/zWWSC8oQEJw
# IDaRXBeF5jAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zATBgNVHSUE
# DDAKBggrBgEFBQcDAzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EMAQQBMEMGA1Ud
# HwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwuY29tb2RvY2EuY29tL0FBQUNlcnRpZmlj
# YXRlU2VydmljZXMuY3JsMDQGCCsGAQUFBwEBBCgwJjAkBggrBgEFBQcwAYYYaHR0
# cDovL29jc3AuY29tb2RvY2EuY29tMA0GCSqGSIb3DQEBDAUAA4IBAQASv6Hvi3Sa
# mES4aUa1qyQKDKSKZ7g6gb9Fin1SB6iNH04hhTmja14tIIa/ELiueTtTzbT72ES+
# BtlcY2fUQBaHRIZyKtYyFfUSg8L54V0RQGf2QidyxSPiAjgaTCDi2wH3zUZPJqJ8
# ZsBRNraJAlTH/Fj7bADu/pimLpWhDFMpH2/YGaZPnvesCepdgsaLr4CnvYFIUoQx
# 2jLsFeSmTD1sOXPUC4U5IOCFGmjhp0g4qdE2JXfBjRkWxYhMZn0vY86Y6GnfrDyo
# XZ3JHFuu2PMvdM+4fvbXg50RlmKarkUT2n/cR/vfw1Kf5gZV6Z2M8jpiUbzsJA8p
# 1FiAhORFe1rYMIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG
# 9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkw
# FwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1
# cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAwMDAwWhcNMzExMTA5MjM1OTU5WjBi
# MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
# d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3Qg
# RzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAi
# MGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnny
# yhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE
# 5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm
# 7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463JT17lNecxy9qTXtyOj4DatpGYQJB5
# w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsD
# dV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1Z
# XUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS0
# 0mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hk
# pjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m8
# 00ERElvlEFDrMcXKchYiCd98THU/Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+i
# sX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB
# /zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4cD08wHwYDVR0jBBgwFoAUReui
# r/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0w
# azAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUF
# BzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVk
# SURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAowCDAG
# BgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9
# mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxS
# A8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtDIeuWcqFItJnLnU+nBgMTdydE1Od/
# 6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlUsLihVo7spNU96LHc/RzY9HdaXFSM
# b++hUD38dglohJ9vytsgjTVgHAIDyyCwrFigDkBjxZgiwbJZ9VVrzyerbHbObyMt
# 9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwYw02fc7cBqZ9Xql4o4rmUMIIGGjCC
# BAKgAwIBAgIQYh1tDFIBnjuQeRUgiSEcCjANBgkqhkiG9w0BAQwFADBWMQswCQYD
# VQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS0wKwYDVQQDEyRTZWN0
# aWdvIFB1YmxpYyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAw
# WhcNMzYwMzIxMjM1OTU5WjBUMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGln
# byBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2RlIFNpZ25pbmcg
# Q0EgUjM2MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAmyudU/o1P45g
# BkNqwM/1f/bIU1MYyM7TbH78WAeVF3llMwsRHgBGRmxDeEDIArCS2VCoVk4Y/8j6
# stIkmYV5Gej4NgNjVQ4BYoDjGMwdjioXan1hlaGFt4Wk9vT0k2oWJMJjL9G//N52
# 3hAm4jF4UjrW2pvv9+hdPX8tbbAfI3v0VdJiJPFy/7XwiunD7mBxNtecM6ytIdUl
# h08T2z7mJEXZD9OWcJkZk5wDuf2q52PN43jc4T9OkoXZ0arWZVeffvMr/iiIROSC
# zKoDmWABDRzV/UiQ5vqsaeFaqQdzFf4ed8peNWh1OaZXnYvZQgWx/SXiJDRSAolR
# zZEZquE6cbcH747FHncs/Kzcn0Ccv2jrOW+LPmnOyB+tAfiWu01TPhCr9VrkxsHC
# 5qFNxaThTG5j4/Kc+ODD2dX/fmBECELcvzUHf9shoFvrn35XGf2RPaNTO2uSZ6n9
# otv7jElspkfK9qEATHZcodp+R4q2OIypxR//YEb3fkDn3UayWW9bAgMBAAGjggFk
# MIIBYDAfBgNVHSMEGDAWgBQy65Ka/zWWSC8oQEJwIDaRXBeF5jAdBgNVHQ4EFgQU
# DyrLIIcouOxvSK4rVKYpqhekzQwwDgYDVR0PAQH/BAQDAgGGMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwEwYDVR0lBAwwCgYIKwYBBQUHAwMwGwYDVR0gBBQwEjAGBgRVHSAA
# MAgGBmeBDAEEATBLBgNVHR8ERDBCMECgPqA8hjpodHRwOi8vY3JsLnNlY3RpZ28u
# Y29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RSNDYuY3JsMHsGCCsGAQUF
# BwEBBG8wbTBGBggrBgEFBQcwAoY6aHR0cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0
# aWdvUHVibGljQ29kZVNpZ25pbmdSb290UjQ2LnA3YzAjBggrBgEFBQcwAYYXaHR0
# cDovL29jc3Auc2VjdGlnby5jb20wDQYJKoZIhvcNAQEMBQADggIBAAb/guF3YzZu
# e6EVIJsT/wT+mHVEYcNWlXHRkT+FoetAQLHI1uBy/YXKZDk8+Y1LoNqHrp22AKMG
# xQtgCivnDHFyAQ9GXTmlk7MjcgQbDCx6mn7yIawsppWkvfPkKaAQsiqaT9DnMWBH
# VNIabGqgQSGTrQWo43MOfsPynhbz2Hyxf5XWKZpRvr3dMapandPfYgoZ8iDL2OR3
# sYztgJrbG6VZ9DoTXFm1g0Rf97Aaen1l4c+w3DC+IkwFkvjFV3jS49ZSc4lShKK6
# BrPTJYs4NG1DGzmpToTnwoqZ8fAmi2XlZnuchC4NPSZaPATHvNIzt+z1PHo35D/f
# 7j2pO1S8BCysQDHCbM5Mnomnq5aYcKCsdbh0czchOm8bkinLrYrKpii+Tk7pwL7T
# jRKLXkomm5D1Umds++pip8wH2cQpf93at3VDcOK4N7EwoIJB0kak6pSzEu4I64U6
# gZs7tS/dGNSljf2OSSnRr7KWzq03zl8l75jy+hOds9TWSenLbjBQUGR96cFr6lEU
# fAIEHVC1L68Y1GGxx4/eRI82ut83axHMViw1+sVpbPxg51Tbnio1lB93079WPFnY
# aOvfGAA0e0zcfF/M9gXr+korwQTh2Prqooq2bYNMvUoUKD85gnJ+t0smrWrb8dee
# 2CvYZXD5laGtaAxOfy/VKNmwuWuAh9kcMIIGMDCCBJigAwIBAgIRAIvbtjfg2Oyh
# 5NMYrimuK+EwDQYJKoZIhvcNAQEMBQAwVDELMAkGA1UEBhMCR0IxGDAWBgNVBAoT
# D1NlY3RpZ28gTGltaXRlZDErMCkGA1UEAxMiU2VjdGlnbyBQdWJsaWMgQ29kZSBT
# aWduaW5nIENBIFIzNjAeFw0yMjAzMjAwMDAwMDBaFw0yNTAzMTMyMzU5NTlaMEYx
# CzAJBgNVBAYTAkRFMQ8wDQYDVQQIDAZCYXllcm4xEjAQBgNVBAoMCU9sYWYgSGVz
# czESMBAGA1UEAwwJT2xhZiBIZXNzMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAqY2qZ6HAtMPpMx1GC4sUFhf0f6q38Vj6wrYCxf5CNfpauYlx7fy5132Z
# Oemmgzw1JPzT8zXCCEarZXH4UFfAJgZvahPNHiEAmC7QGBw8Usxxso4avCB/LxKZ
# cpKrpfZ7NNXUCJBAFZiKwefE+Q2t7JsSp7h3LmDWDXCqp27KrPmQSBh+OI7sLa2C
# heBl49OxhQFJiDBcT6qqV28gDJr6wrO2Ym0Ep8X//EAyDZUl04wy1d6OhCizInAc
# ML9MKpW446/Db6313mPzAd1YvmYl8VUCdKNLyCC+/GjoBd8NeO38T/jsHAvRWO+A
# liihXQlwi/lDeM+FwBIvnZLQnDDKK0cFxBDfBIvEUp0RI6L5JP7KiBfCkB63msiB
# +Lr2xxQMORXAjIbvGkaGj6XjOwGqUl2ZLcTEa3T1Rf+E8+h9ZJ6L8/vfJ5xiRmDH
# PgjWJfpS9j9YKTf6CNcOnvfKcOqkivVJEnd2gf7zbMnJZ/UI3RGfLP9l7t5DJMyW
# Ekl1lGUrtVpI6+C1/r6ivVWAxcA8VhII+u3j8n+He+q4eiN/L++KyWCz6hUIPtYf
# nLpKG5qUUkKguUPj7vAN24eFZQK0Th/CR87kKRJYS77czH7EeAs5vR21oen4sCc4
# SnxGFXoS0x0azglrY6FTDFCH1cPiSlPTAK90P3WFmXr54BLNP0sCAwEAAaOCAYkw
# ggGFMB8GA1UdIwQYMBaAFA8qyyCHKLjsb0iuK1SmKaoXpM0MMB0GA1UdDgQWBBSN
# VUuC59Ore8exoePVr4+wCOyrnzAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIw
# ADATBgNVHSUEDDAKBggrBgEFBQcDAzBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgED
# AjAlMCMGCCsGAQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwB
# BAEwSQYDVR0fBEIwQDA+oDygOoY4aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0
# aWdvUHVibGljQ29kZVNpZ25pbmdDQVIzNi5jcmwweQYIKwYBBQUHAQEEbTBrMEQG
# CCsGAQUFBzAChjhodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWND
# b2RlU2lnbmluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2Vj
# dGlnby5jb20wDQYJKoZIhvcNAQEMBQADggGBACwr9pJKFCQgdcCJ/57RzqjMqCoc
# iHic6CF7cCCCPjmR8E/S5k3s/C0kDsDsDZ2SbhIWMRHAOUd55qf3lu7tSOa6PdUE
# tjL4XASJpL2SX8wmKKc0Pd0BPhqRx5Yi7u5o5R5ZQR+iK5kA9ZUTBTFnInfarUf7
# HKpDuhwA/azDkKcHWe/camVPO5e7EOHr8NiNP8UUPMR+J57TwNdZ0wEKoUe1GqHE
# rdokUqr9QdQoPx+zuc2VLNAYlbpdum4uThakugMsHEeuFMvgsAdo7J+iGFI+tCDR
# 9xxcP7eUBbVMhe//iIMwU+Ec1PQCAT09NlsMRg8taPaeYlzZTgU8uZAAGfmprnNU
# l79DO/A/8mKAWH+uyEuOYClIkB3aZmnIgJwldT49YWx+ogsJ9L8JhQzncPSxd5vl
# 6yH1AMB2sAjH44ieq7QKjBTFWSaKxrhj3/c4C7ONJ4FAg3weSehY2Yax/9Rxjou2
# REH+sgVyxxYJM8eANK/0FrSAGj0XT5a18xfzuDCCBq4wggSWoAMCAQICEAc2N7ck
# VHzYR6z9KGYqXlswDQYJKoZIhvcNAQELBQAwYjELMAkGA1UEBhMCVVMxFTATBgNV
# BAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8G
# A1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MB4XDTIyMDMyMzAwMDAwMFoX
# DTM3MDMyMjIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0
# LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hB
# MjU2IFRpbWVTdGFtcGluZyBDQTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBAMaGNQZJs8E9cklRVcclA8TykTepl1Gh1tKD0Z5Mom2gsMyD+Vr2EaFEFUJf
# pIjzaPp985yJC3+dH54PMx9QEwsmc5Zt+FeoAn39Q7SE2hHxc7Gz7iuAhIoiGN/r
# 2j3EF3+rGSs+QtxnjupRPfDWVtTnKC3r07G1decfBmWNlCnT2exp39mQh0YAe9tE
# QYncfGpXevA3eZ9drMvohGS0UvJ2R/dhgxndX7RUCyFobjchu0CsX7LeSn3O9TkS
# Z+8OpWNs5KbFHc02DVzV5huowWR0QKfAcsW6Th+xtVhNef7Xj3OTrCw54qVI1vCw
# MROpVymWJy71h6aPTnYVVSZwmCZ/oBpHIEPjQ2OAe3VuJyWQmDo4EbP29p7mO1vs
# gd4iFNmCKseSv6De4z6ic/rnH1pslPJSlRErWHRAKKtzQ87fSqEcazjFKfPKqpZz
# QmiftkaznTqj1QPgv/CiPMpC3BhIfxQ0z9JMq++bPf4OuGQq+nUoJEHtQr8FnGZJ
# UlD0UfM2SU2LINIsVzV5K6jzRWC8I41Y99xh3pP+OcD5sjClTNfpmEpYPtMDiP6z
# j9NeS3YSUZPJjAw7W4oiqMEmCPkUEBIDfV8ju2TjY+Cm4T72wnSyPx4JduyrXUZ1
# 4mCjWAkBKAAOhFTuzuldyF4wEr1GnrXTdrnSDmuZDNIztM2xAgMBAAGjggFdMIIB
# WTASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBS6FtltTYUvcyl2mi91jGog
# j57IbzAfBgNVHSMEGDAWgBTs1+OC0nFdZEzfLmc/57qYrhwPTzAOBgNVHQ8BAf8E
# BAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwgwdwYIKwYBBQUHAQEEazBpMCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUHMAKGNWh0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQu
# Y3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydFRydXN0ZWRSb290RzQuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAfVmOwJO2b5ipRCIBfmbW2CFC
# 4bAYLhBNE88wU86/GPvHUF3iSyn7cIoNqilp/GnBzx0H6T5gyNgL5Vxb122H+oQg
# JTQxZ822EpZvxFBMYh0MCIKoFr2pVs8Vc40BIiXOlWk/R3f7cnQU1/+rT4osequF
# zUNf7WC2qk+RZp4snuCKrOX9jLxkJodskr2dfNBwCnzvqLx1T7pa96kQsl3p/yhU
# ifDVinF2ZdrM8HKjI/rAJ4JErpknG6skHibBt94q6/aesXmZgaNWhqsKRcnfxI2g
# 55j7+6adcq/Ex8HBanHZxhOACcS2n82HhyS7T6NJuXdmkfFynOlLAlKnN36TU6w7
# HQhJD5TNOXrd/yVjmScsPT9rp/Fmw0HNT7ZAmyEhQNC3EyTN3B14OuSereU0cZLX
# JmvkOHOrpgFPvT87eK1MrfvElXvtCl8zOYdBeHo46Zzh3SP9HSjTx/no8Zhf+yvY
# fvJGnXUsHicsJttvFXseGYs2uJPU5vIXmVnKcPA3v5gA3yAWTyf7YGcWoWa63VXA
# OimGsJigK+2VQbc61RWYMbRiCQ8KvYHZE/6/pNHzV9m8BPqC3jLfBInwAM1dwvnQ
# I38AC+R2AibZ8GV2QqYphwlHK+Z/GqSFD/yYlvZVVCsfgPrA8g4r5db7qS9EFUrn
# Ew4d2zc4GqEr9u3WfPwwggbCMIIEqqADAgECAhAFRK/zlJ0IOaa/2z9f5WEWMA0G
# CSqGSIb3DQEBCwUAMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2IFNIQTI1
# NiBUaW1lU3RhbXBpbmcgQ0EwHhcNMjMwNzE0MDAwMDAwWhcNMzQxMDEzMjM1OTU5
# WjBIMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xIDAeBgNV
# BAMTF0RpZ2lDZXJ0IFRpbWVzdGFtcCAyMDIzMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEAo1NFhx2DjlusPlSzI+DPn9fl0uddoQ4J3C9Io5d6OyqcZ9xi
# FVjBqZMRp82qsmrdECmKHmJjadNYnDVxvzqX65RQjxwg6seaOy+WZuNp52n+W8PW
# KyAcwZeUtKVQgfLPywemMGjKg0La/H8JJJSkghraarrYO8pd3hkYhftF6g1hbJ3+
# cV7EBpo88MUueQ8bZlLjyNY+X9pD04T10Mf2SC1eRXWWdf7dEKEbg8G45lKVtUfX
# eCk5a+B4WZfjRCtK1ZXO7wgX6oJkTf8j48qG7rSkIWRw69XloNpjsy7pBe6q9iT1
# HbybHLK3X9/w7nZ9MZllR1WdSiQvrCuXvp/k/XtzPjLuUjT71Lvr1KAsNJvj3m5k
# GQc3AZEPHLVRzapMZoOIaGK7vEEbeBlt5NkP4FhB+9ixLOFRr7StFQYU6mIIE9Np
# HnxkTZ0P387RXoyqq1AVybPKvNfEO2hEo6U7Qv1zfe7dCv95NBB+plwKWEwAPoVp
# dceDZNZ1zY8SdlalJPrXxGshuugfNJgvOuprAbD3+yqG7HtSOKmYCaFxsmxxrz64
# b5bV4RAT/mFHCoz+8LbH1cfebCTwv0KCyqBxPZySkwS0aXAnDU+3tTbRyV8IpHCj
# 7ArxES5k4MsiK8rxKBMhSVF+BmbTO77665E42FEHypS34lCh8zrTioPLQHsCAwEA
# AaOCAYswggGHMA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB
# /wQMMAoGCCsGAQUFBwMIMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwH
# ATAfBgNVHSMEGDAWgBS6FtltTYUvcyl2mi91jGogj57IbzAdBgNVHQ4EFgQUpbbv
# E+fvzdBkodVWqWUxo97V40kwWgYDVR0fBFMwUTBPoE2gS4ZJaHR0cDovL2NybDMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0UlNBNDA5NlNIQTI1NlRpbWVT
# dGFtcGluZ0NBLmNybDCBkAYIKwYBBQUHAQEEgYMwgYAwJAYIKwYBBQUHMAGGGGh0
# dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBYBggrBgEFBQcwAoZMaHR0cDovL2NhY2Vy
# dHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0UlNBNDA5NlNIQTI1NlRp
# bWVTdGFtcGluZ0NBLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAgRrW3qCptZgXvHCN
# T4o8aJzYJf/LLOTN6l0ikuyMIgKpuM+AqNnn48XtJoKKcS8Y3U623mzX4WCcK+3t
# PUiOuGu6fF29wmE3aEl3o+uQqhLXJ4Xzjh6S2sJAOJ9dyKAuJXglnSoFeoQpmLZX
# eY/bJlYrsPOnvTcM2Jh2T1a5UsK2nTipgedtQVyMadG5K8TGe8+c+njikxp2oml1
# 01DkRBK+IA2eqUTQ+OVJdwhaIcW0z5iVGlS6ubzBaRm6zxbygzc0brBBJt3eWpdP
# M43UjXd9dUWhpVgmagNF3tlQtVCMr1a9TMXhRsUo063nQwBw3syYnhmJA+rUkTfv
# TVLzyWAhxFZH7doRS4wyw4jmWOK22z75X7BC1o/jF5HRqsBV44a/rCcsQdCaM0qo
# NtS5cpZ+l3k4SF/Kwtw9Mt911jZnWon49qfH5U81PAC9vpwqbHkB3NpE5jreODsH
# XjlY9HxzMVWggBHLFAx+rrz+pOt5Zapo1iLKO+uagjVXKBbLafIymrLS2Dq4sUaG
# a7oX/cR3bBVsrquvczroSUa31X/MtjjA2Owc9bahuEMs305MfR5ocMB3CtQC4Fxg
# uyj/OOVSWtasFyIjTvTs0xf7UGv/B3cfcZdEQcm4RtNsMnxYL2dHZeUbc7aZ+Wss
# BkbvQR7w8F/g29mtkIBEr4AQQYoxggYuMIIGKgIBATBpMFQxCzAJBgNVBAYTAkdC
# MRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVi
# bGljIENvZGUgU2lnbmluZyBDQSBSMzYCEQCL27Y34NjsoeTTGK4privhMAkGBSsO
# AwIaBQCgeDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEM
# BgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqG
# SIb3DQEJBDEWBBSoyMVstSqgmm73EUjGtA0rB2nAEjANBgkqhkiG9w0BAQEFAASC
# AgAgTK+OuY9RIIj1nl69nzSp1ePBJyqr60PL8DY3pxP39T+FDd1Dfl1zPXWsJJQw
# Y43i3Oruyrk3fmMQtYtSiSGUYj7Fol1Sj2+Qh1andUGlm+g40l4X0r0AyblvMTdU
# EpK3/eVa0MR/noRcjZ3IpmlX1EZTVrHyACMPuG6Jii2qg3/CuMaWvpZ/iGLXJgGl
# sUFIDhMkXoEV9VEVndi0vDlWDM71km0NQBEIhPQP+Wpuon7C4bndTzyV09IxJayD
# ENL8d0jB8pLOgUBXhc9kEL89/bZkMHzm4cBqtqlvl06tbuBkVSlkZvLWF2YpE4+4
# 4fuxBuw7wgIL7yYBAYtdhuXgLQrDa66tw0ZgzJeDojQ8/FP4ctHgJtijgejQFTlf
# KS1+kAzOk4mx6iTEL2h7WVaLyli8/D8HxbO39hb76U/GIVIaNcCkoDq61JKT2NcS
# rcamYpu91q2kaV01tiaHYB5+R22Caou9bIdxeUULPYLcnV5oB/O26O4WkzYRblxZ
# qYwqVISlwMWNVLhzDvbBuWgtfdq4HjKnO7wuHEVEoiyKqbVOlnxdkTk9cECHkEbF
# vWDbVi2Sb4qCf37/yLvY0I+S5+/dF1VnbmXu3XN1oYWJprJGCIwg+kyCgEoa0W0G
# LIGb1/t+c79Y+c2E9Uk5hlPSreUc59awR5jyB7redR32D6GCAyAwggMcBgkqhkiG
# 9w0BCQYxggMNMIIDCQIBATB3MGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2
# IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0ECEAVEr/OUnQg5pr/bP1/lYRYwDQYJYIZI
# AWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJ
# BTEPFw0yNDA3MDExMDUyNTZaMC8GCSqGSIb3DQEJBDEiBCCOG7Y6HHe/u6IW2lxg
# +Web2HGdHjmyUMWY+Y+nBDvyTzANBgkqhkiG9w0BAQEFAASCAgAOe+nTujL7BtIy
# H7H/RgFJXD+6/D8IYheOTxljIGW0p03nk3OLzy94hSMV1INMX9QsYG56i+IQV5tm
# A3fg9nRugESKxayYdhcnA0APKufQN0HGmBfv4qmxNxwBze9Otj1svLaBiuxURJr5
# y4o3Hfo9vF1wNPSdYMz6s7gI3ICQ5hL33X1PvmmJM/JTTlNJkTetRr8gAywuxIM6
# 0pswyGjQM20M3yKTd2WlcHGGEJwPXbL1AxUdiOkMpstUaR/c/oq6iBGEVxWxCPKc
# kmzaFV+YGPRWg096Yn71RcssFtTlxkYXfKnaVhifhFyh2CriO0exiWWaVqZlprxV
# oaK4PgHI82Ybv/UFwaGTRqWf5p6N/xvnT+nyRU5OiW0UFUJQvuQzluvhuRTt8KuR
# RIZri4rwGxUowPy0N29MbxljLUx4FvumyYBNQ+cyYJlYecgeEY0vuaVzkTX41CrO
# lm/mUYPRMvRq3Ufz+unp4/xKcQXFclOnNHoChxoPb8CgXeYsz6JvEF0r0WzfS/N6
# G8yJfqNu+lv6D0DcFtBdX31jfvkPB0HHT/rmWCa6eTe59J91d7Yox6l0fRfNIeVx
# Jtg1ozSYPCpaCvoDbkSDymb0+QkJS/lYO6zF/zqB4yq/C90t5zToqhfErHKsoC6b
# txgwdcc3pBR6rpJULIzow3UIUVB8NQ==
# SIG # End signature block
