#------------------------------------------------------------------------------
# FILE:         action.ps1
# CONTRIBUTOR:  Jeff Lill
# COPYRIGHT:    Copyright (c) 2005-2021 by neonFORGE LLC.  All rights reserved.
#
# The contents of this repository are for private use by neonFORGE, LLC. and may not be
# divulged or used for any purpose by other organizations or individuals without a
# formal written and signed agreement with neonFORGE, LLC.

#------------------------------------------------------------------------------
# Sends a test related notification message to a Microsoft Teams channel URI.
#
# INPUTS:
#
#   channel             - Target Teams channel webhook URI
#   start-time          - Time when the tests started (formatted like YYYY-MM-DD HH-MM:SSZ)
#   finish-time         - Time when the tests completed (formatted like YYYY-MM-DD HH-MM:SSZ)
#   build-branch        - Indicates which target repo branch was built
#   build-commit        - Optionally specifies the build commit
#   build-commit-uri    - Optionally specifies target repo commit URI
#   test-summary        - Identifies what's being tested
#   test-outcome        - Test step outcome, one of: 'success', 'failure', 'cancelled', or 'skipped'
#   test-success        - Indicates whether the tests all succeeded or failed
#   send-on             - Optionally specifies the conditions when a notification can be sent.
#                         This can be one or more of the following values separated by spaces:
#
#                               always          - send always
#                               failure         - send when the build step outcome is 'success'
#                               failure         - send when the build step outcome is 'failure'
#                               cancelled       - send when the build step outcome is 'cancelled'
#                               skipped         - send when the build step outcome is 'skipped'
#                               test-success    - send when the actual test (vs. the step) succeeded
#                               test-fail       - send when the actual test (vs. the step) failed
    
# Verify that we're running on a properly configured neonFORGE jobrunner 
# and import the deployment and action scripts from neonCLOUD.

# NOTE: This assumes that the required [$NC_ROOT/Powershell/*.ps1] files
#       in the current clone of the repo on the runner are up-to-date
#       enough to be able to obtain secrets and use GitHub Action functions.
#       If this is not the case, you'll have to manually pull the repo 
#       first on the runner.

$ncRoot = $env:NC_ROOT

if ([System.String]::IsNullOrEmpty($ncRoot) -or ![System.IO.Directory]::Exists($ncRoot))
{
    throw "Runner Config: neonCLOUD repo is not present."
}

$ncPowershell = [System.IO.Path]::Combine($ncRoot, "Powershell")

Push-Location $ncPowershell
. ./includes.ps1
Pop-Location

# Implement the operation.

try
{    
    # Fetch the inputs.

    $channel        = Get-ActionInput "channel"          $true
    $buildBranch    = Get-ActionInput "build-branch"     $false
    $buildCommit    = Get-ActionInput "build-commit"     $false
    $buildCommitUri = Get-ActionInput "build-commit-uri" $false
    $startTime      = Get-ActionInput "start-time"       $false
    $finishTime     = Get-ActionInput "finish-time"      $false
    $testSummary    = Get-ActionInput "test-summary"     $true
    $testOutcome    = Get-ActionInput "test-outcome"     $true
    $testSuccess    = $(Get-ActionInput "test-success" $true) -eq "true"
    $testFilter     = Get-ActionInput "test-filter"      $false
    $testResultUris = Get-ActionInput "test-result-uris" $false
    $testResultInfo = Get-ActionInput "test-result-info" $false
    $workflowRef    = Get-ActionInput "workflow-ref"     $true
    $sendOn         = Get-ActionInput "send-on"          $true

    # Exit if the notification shouldn't be transmitted based on the test step outcome
    # and its success output.  We're going to do a simple string match here rather than 
    # parsing [send-on].

    $sendAlways = $sendOn.Contains("always")

    if (!$sendAlways -and !$sendOn.Contains($testOutcome))
    {
        # Handle the test-success/fail build step result.

        if ($testSuccess -and $sendOn.Contains("test-success"))
        {
            # Send the notification below.
        }
        elseif (!$testSuccess -and $sendOn.Contains("test-fail"))
        {
            # Send the notification below.
        }
        else 
        {
            # Exit so we don't send a notification.

            return
        }
    }

    # Handle missing [build-branch] and [build-commit-uri] inputs.

    if ([System.String]::IsNullOrEmpty($buildBranch))
    {
        $buildBranch = "-na-"
    }
    else
    {
        $buildBranch = "**$buildBranch**"
    }

    if ([System.String]::IsNullOrEmpty($buildCommit) -or [System.String]::IsNullOrEmpty($buildCommitUri))
    {
        $buildCommitUri = "-na-"
    }
    else
    {
        $buildCommitUri = "[$buildCommit]($buildCommitUri)"
    }

    # Parse the optional start/finish times and compute the elapsed time.  Note that
    # we're going to display "-na" when either of these timestamps were not passed.

    if ([System.String]::IsNullOrEmpty($startTime) -or [System.String]::IsNullOrEmpty($finishTime))
    {
        $startTime   = "-na-"
        $finishTime  = "-na-"
        $elapsedTime = "-na-"
    }
    else
    {
        $startTime   = [System.DateTime]::Parse($startTime).ToString("u")
        $finishTime  = [System.DateTime]::Parse($finishTime).ToString("u")
        $elapsedTime = $(New-TimeSpan $startTime $finishTime).ToString("c")
    }

    # Determine the workflow run URI.

    $workflowRunUri = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"

    # Convert [$workflowRef] into the URI to referencing the correct workflow branch.  We're
    # going to use the GITHUB_REF environment variable.  This includes the branch like:
    #
    #       refs/heads/master
    #
    # Note that the workflow may be executing on a different branch than the repo build.

    if (!$workflowRef.Contains("/blob/master/"))
    {
        throw "[workflow-ref=$workflowRef] is missing '/blob/master/'."
    }

    $githubRef      = $env:GITHUB_REF
    $lastSlashPos   = $githubRef.LastIndexOf("/")
    $workflowBranch = $githubRef.Substring($lastSlashPos + 1)
    $workflowUri    = $workflowRef.Replace("/blob/master/", "/blob/$workflowBranch/")

    # Determine the reason why the workflow was triggered based on the GITHUB_EVENT_NAME
    # and GITHUB_ACTOR environment variables.

    $eventName = $env:GITHUB_EVENT_NAME
    $actor     = $env:GITHUB_ACTOR

    if (![System.String]::IsNullOrEmpty($actor))
    {
        $actor = $actor.ToUpper()
    }

    if (![System.String]::IsNullOrEmpty($eventName))
    {
        $eventName = $eventName.ToUpper()
    }

    if ($eventName -eq "workflow_dispatch")
    {
        $trigger = "Started by: **$actor**"
    }
    else
    {
        $trigger = "Event trigger: **$eventName**"
    }

    # Set the theme color based on the build outcome/success inputs.

    $themeColor = "ff0000" # green

    Switch ($testOutcome)
    {
        "success"
        {
            $themeColor = "00ff00" # green
        }

        "cancelled"
        {
            $themeColor = "ffa500" # orange
        }

        "skipped"
        {
            $themeColor = "ffa500" # orange
        }

        "failure"
        {
            $themeColor = "ff0000" # red
        }
    }

    if (!$testSuccess)
    {
        $themeColor  = "ff0000" # red
        $testOutcome = "TESTS FAILED"
    }

    # Format $testOutcome

    $testOutcome = "**$testOutcome**"

    # This is the legacy MessageCard format (Adaptive Cards are not supported by
    # the Teams Connector at this time):
    #
    #   https://docs.microsoft.com/en-us/outlook/actionable-messages/message-card-reference

    $card = 
@'
{
  "@type": "MessageCard",
  "@context": "https://schema.org/extensions",
  "themeColor": "@theme-color",
  "summary": "@build-summary",
  "sections": [
    {
      "activityTitle": "@test-summary",
      "activitySubtitle": "@trigger",
    },
    {
      "facts": [
         {
           "name": "Outcome:",
           "value": "@test-outcome"
         },
         {
           "name": "Filter:",
           "value": "@filter"
         },
         {
           "name": "Branch:",
           "value": "@build-branch"
         },
         {
           "name": "Commit:",
           "value": "@build-commit-uri"
         },
         {
           "name": "Runner:",
           "value": "@runner"
         },
         {
           "name": "Finished:",
           "value": "@finish-time"
         },
         {
           "name": "Elapsed:",
           "value": "@elapsed-time"
         }
       ]
     },
     {
       "startGroup": true,
       "facts": [
@result-facts
       ]
     }
   ],
   "potentialAction": [
     {
       "@type": "OpenUri",
       "name": "Show Workflow Run",
       "targets": [
         {
           "os": "default",
           "uri": "@workflow-run-uri"
         }
       ]
     },
     {
        "@type": "OpenUri",
        "name": "Show Workflow",
        "targets": [
           {
             "os": "default",
             "uri": "@workflow-uri"
           }
        ]
     }
   ]
}    
'@

    $card = $card.Replace("@test-summary", $testSummary)
    $card = $card.Replace("@trigger", $trigger)
    $card = $card.Replace("@runner", $env:COMPUTERNAME)
    $card = $card.Replace("@filter", $filter)
    $card = $card.Replace("@build-branch", $buildBranch)
    $card = $card.Replace("@build-commit-uri", $buildCommitUri)
    $card = $card.Replace("@test-outcome", $testOutcome.ToUpper())
    $card = $card.Replace("@workflow-run-uri", $workflowRunUri)
    $card = $card.Replace("@workflow-uri", $workflowUri)
    $card = $card.Replace("@finish-time", $finishTime)
    $card = $card.Replace("@elapsed-time", $elapsedTime)
    $card = $card.Replace("@theme-color", $themeColor)

    # Generate the card facts for each of test result (if passed)
    # to this action and insert these into the card.

    $okStatus      = "\u2714"       # heavy checkmark (JSON encoded)
    $warningStatus = "\u26A0"       # warning sign (JSON encoded)
    $errorStatus   = "\u274C"       # error cross (JSON encoded)
    $resultFacts   = ""

    if (![System.String]::IsNullOrEmpty($testResultUris) -and ![System.String]::IsNullOrEmpty($testResultInfo))
    {
        $resultUris = $testResultUris.Split(";")
        $resultInfo = $testResultInfo.Split(";")

        if ($resultUris.Length -eq $resultInfo.Length)
        {
            For ($i = 0 ; $i -lt $resultUris.Length ; $i++)
            {
                $resultUri = $resultUris[$i]

                # Extract the statistics from the corresponding summary.

                $details = $resultInfo[$i].Split(",")
                $name    = $details[0]
                $total   = [int]$details[1]
                $errors  = [int]$details[2]
                $skips   = [int]$details[3]
                $elapsed = $details[4]

                # Initialize the fact JSON for the test project.

                $factTemplate = 
@'
         {
           "name": "@test-project:",
           "value": "@status-uri **@result-uri** - @elapsed pass: **@pass** fail: **@fail** skipped: @skip"
         }
'@
                $factTemplate = $factTemplate.Replace("@test-project", $name)
                $factTemplate = $factTemplate.Replace("@result-uri", $resultUri)

                if ($errors -gt 0)
                {
                    $statusUri = $errorStatus
                }
                elseif ($skips -gt 0)
                {
                    $statusUri = $warningStatus
                }
                else
                {
                    $statusUri = $okStatus
                }

                # Replace the statistics related fact placeholders.

                $factTemplate = $factTemplate.Replace("@status-uri", $statusUri)
                $factTemplate = $factTemplate.Replace("@elapsed", $elapsed)
                $factTemplate = $factTemplate.Replace("@pass", $total - $errors - $skips)
                $factTemplate = $factTemplate.Replace("@fail", $errors)
                $factTemplate = $factTemplate.Replace("@skip", $skips)

                # Append the new test fact to the result facts that we'll
                # insert into the card below.

                if ($i -lt $resultUris.Length - 1)
                {
                    $factTemplate += ","
                }

                $resultFacts += $factTemplate
            }
        }
    }
    else
    {
        # We didn't get any results from the test step, so we'll add
        # fact saying this.

        $noResultsFact =
@'
            {
              "name": "Results:",
              "value": "**none** (no available test results)"
            }
'@
        $resultFacts += $noResultsFact
    }

    # Insert the test result facts into the card.

    $card = $card.Replace("@result-facts", $resultFacts)

    # Post the card to Microsoft Teams.

    Invoke-WebRequest -Method "POST" -Uri $channel -ContentType "application/json" -Body $card | Out-Null
}
catch
{
    Write-ActionException $_
    exit 1
}
