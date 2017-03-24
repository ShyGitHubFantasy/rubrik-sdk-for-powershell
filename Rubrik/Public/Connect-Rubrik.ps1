﻿#Requires -Version 3
function Connect-Rubrik 
{
  <#  
      .SYNOPSIS
      Connects to Rubrik and retrieves a token value for authentication

      .DESCRIPTION
      The Connect-Rubrik function is used to connect to the Rubrik RESTful API and supply credentials to the /login method.
      Rubrik then returns a unique token to represent the user's credentials for subsequent calls.
      Acquire a token before running other Rubrik cmdlets.
      Note that you can pass a username and password or an entire set of credentials.

      .NOTES
      Written by Chris Wahl for community usage
      Twitter: @ChrisWahl
      GitHub: chriswahl

      .LINK
      https://github.com/rubrikinc/PowerShell-Module

      .EXAMPLE
      Connect-Rubrik -Server 192.168.1.1 -Username admin
      This will connect to Rubrik with a username of "admin" to the IP address 192.168.1.1.
      The prompt will request a secure password.

      .EXAMPLE
      Connect-Rubrik -Server 192.168.1.1 -Username admin -Password (ConvertTo-SecureString "secret" -asplaintext -force)
      If you need to pass the password value in the cmdlet directly, use the ConvertTo-SecureString function.

      .EXAMPLE
      Connect-Rubrik -Server 192.168.1.1 -Credential (Get-Credential)
      Rather than passing a username and secure password, you can also opt to submit an entire set of credentials using the -Credentials parameter.
  #>

  [CmdletBinding()]
  Param(
    # The IP or FQDN of any available Rubrik node within the cluster
    [Parameter(Mandatory = $true,Position = 0)]
    [ValidateNotNullorEmpty()]
    [String]$Server,
    # Username with permissions to connect to the Rubrik cluster
    # Optionally, use the Credential parameter
    [Parameter(Position = 1)]
    [String]$Username,
    # Password for the Username provided
    # Optionally, use the Credential parameter
    [Parameter(Position = 2)]
    [SecureString]$Password,
    # Credentials with permission to connect to the Rubrik cluster
    # Optionally, use the Username and Password parameters
    [Parameter(Position = 3)]
    [System.Management.Automation.CredentialAttribute()]$Credential

  )

  Begin {

    Unblock-SelfSignedCert
        
    Write-Verbose -Message 'Gather API data'
    $resources = Get-RubrikAPIData -endpoint ('Session')
  
  }

  Process {

    $Credential = Test-RubrikCredential -Username $Username -Password $Password -Credential $Credential

    foreach ($versionnum in $resources.Keys | Sort-Object -Descending)
    {
      # Load the version specific data from the resources array
      $version = $resources[$versionnum]
      
      Write-Verbose -Message "Connecting to $($version.URI)"
    
      # Create the URI
      $uri = 'https://'+$Server+$version.URI
      
      # Set the Method
      $method = $version.Method      
      
      # For API version v0 and v1.0, create a body with the credentials
      if ($versionnum -eq 'v0' -or $versionnum -eq 'v1.0') 
      {
        $body = @{
          $version.Body[0] = $Credential.UserName
          $version.Body[1] = $Credential.GetNetworkCredential().Password
        }
      }
      # For API version v1.1 or greater, use a standard Basic Auth Base64 encoded header with username:password
      else 
      {
        $auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Credential.UserName+':'+$Credential.GetNetworkCredential().Password))
        $head = @{
          'Authorization' = "Basic $auth"
        }      
      }

      Write-Verbose -Message 'Submitting the request'
      try 
      {
        $r = Invoke-WebRequest -Uri $uri -Method $method -Body (ConvertTo-Json -InputObject $body) -Headers $head
        $content = (ConvertFrom-Json -InputObject $r.Content)
        # If we find a successful call code and also a token, we know the request was successful
        # Anything else will trigger a throw, which will cause the catch to break the current loop and try another version
        if ($r.StatusCode -eq $version.SuccessCode -and $content.token -ne $null)
        {
          Write-Verbose -Message "Successfully acquired token: $($content.token)"
          break
        }
        else
        {
          throw 'Unable to connect to the cluster'
        }
      }
      catch 
      {

      }
    }
    
    # Final throw for when all versions of the API have failed
    if ($content.token -eq $null) 
    {
      throw 'Unable to connect with any available API version'
    }

    # For API version v0 and v1.0, use a standard Basic Auth Base64 encoded header with token:$null
    if ($versionnum -eq 'v0' -or $versionnum -eq 'v1.0') 
    {
      Write-Verbose -Message 'Validate token and build Base64 Auth string'
      $auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($($content.token)+':'))
      $head = @{
        'Authorization' = "Basic $auth"
      }
    }
    # For API version v1.1 or greater, use Bearer and token
    else 
    {
      $head = @{
        'Authorization' = "Bearer $($content.token)"
      }
    }

    # v1.0 uses a different auth method compared to v1.1
    # If we find v1.1 is in use, reset the version number to 'v1' to match the remainder of v1 calls
    if ($versionnum -match 'v1')
    {
      $versionnum = 'v1'
    }

    Write-Verbose -Message 'Storing all connection details into $global:rubrikConnection'
    $global:rubrikConnection = @{
      userId = $content.userId
      token  = $content.token
      server = $Server
      header = $head
      time   = (Get-Date)
      api    = $versionnum
    }
        
    Write-Verbose -Message 'Adding connection details into the $global:RubrikConnections array'
    [array]$global:RubrikConnections += $rubrikConnection
    
    $global:rubrikConnection.GetEnumerator() | Where-Object -FilterScript {
      $_.name -notmatch 'token'
    }

  } # End of process
} # End of function