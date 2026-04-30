# Docling API Credential Setup

This project should use Salesforce's preferred **External Credential + Named Credential** pattern for the Render-hosted Docling service.

Current status, 2026-04-29:

- `Spread_Docling_Service_V2` is the active Named Credential.
- The Agentforce org has working credentials.
- `ExtractionQueueable` uses `callout:Spread_Docling_Service_V2/extract`.
- `DoclingKeepWarmSchedulable` calls `/health`.
- Transient Render loading failures now retry before final extraction failure.

## Target Pattern

- External Credential: custom authentication, named principal
- Principal secret: Docling API key
- Custom header: `Api-Key`
- Named Credential: `Spread_Docling_Service_V2`
- Apex endpoint usage: `callout:Spread_Docling_Service_V2/...`

## Why this pattern

Salesforce officially recommends the improved Named Credentials model introduced with External Credentials instead of legacy named credentials. For API-key services, Salesforce documents a custom-auth external credential with the API key stored as a principal authentication parameter and referenced from a custom header formula.

Official sources:

- https://developer.salesforce.com/docs/platform/named-credentials/guide/get-started.html
- https://help.salesforce.com/s/articleView?id=xcloud.nc_custom_headers_and_api_keys.htm&language=en_US&type=5
- https://developer.salesforce.com/docs/platform/named-credentials/guide/nc-package-credentials.html
- https://developer.salesforce.com/docs/platform/named-credentials/guide/nc-populate-external-credentials.html

## Org Setup Steps

1. Create an External Credential.
2. Set Authentication Protocol to `Custom`.
3. Create a named principal for the shared Docling API key.
4. Add an authentication parameter on that principal, for example `DoclingApiKey`.
5. Create a custom header named `Api-Key`.
6. Set the custom header value to a formula that references the stored secret.

Example shape from Salesforce's documented pattern:

```text
{!$Credential.<ExternalCredentialApiName>.<ParameterName>}
```

For this service, the final header value should resolve to only the secret value, because the Docling service expects:

```http
Api-Key: <actual-secret>
```

7. Create or update the Named Credential named `Spread_Docling_Service_V2`.
8. Point it to the Render base URL, for example:

```text
https://spread-docling-service.onrender.com
```

9. Disable generated authorization headers so the custom `Api-Key` header is used.
10. Assign the external credential principal to the integration user's permission set or the analyst permission set used for testing.

## Secret Population

The secret itself is not packageable. Salesforce documents that external credential principals must be populated in the target org after deployment, either through Setup or the Connect API.

That means the repo can safely hold:

- the named credential metadata
- the external credential metadata
- the permission-set access

But the actual API key value must be entered in the org.

## Render Setup

Set these Render environment variables:

```text
DOCLING_API_KEY=<same-secret-stored-in-salesforce>
REQUIRE_API_KEY=true
```

Recommended service behavior for sandbox testing:

- Keep `/health` lightweight and authenticated.
- Return HTTP 200 only when the app is ready to accept extraction requests.
- Keep native PDF text extraction enabled for text-layer PDFs.
- Use clear 4xx errors for credential or request issues.
- Treat 502/503/504 and chunk termination as transient from Salesforce.

## Validation

After the org and Render are configured, validate with the Apex credential probe:

```apex
System.debug(SpreadDoclingCredentialService.checkAuthorizedConnection());
```

Expected result:

- HTTP 200
- body contains `authorized`

After that, retry extraction on a pilot document.

## Keep-Warm Schedule

The Agentforce org currently schedules `DoclingKeepWarmSchedulable` every 10 minutes through six cron jobs:

- `Docling Keep Warm 00`
- `Docling Keep Warm 10`
- `Docling Keep Warm 20`
- `Docling Keep Warm 30`
- `Docling Keep Warm 40`
- `Docling Keep Warm 50`

If extraction starts failing with Render loading pages, verify:

```soql
SELECT Id, CronJobDetail.Name, State, NextFireTime, PreviousFireTime, TimesTriggered
FROM CronTrigger
WHERE CronJobDetail.Name LIKE 'Docling Keep Warm%'
ORDER BY NextFireTime ASC
```

## Transient Failure Handling

The extraction queueable retries these transient conditions before marking the document failed:

- HTTP 502, 503, or 504.
- Render `Application loading` page.
- Premature chunk termination.
- Timeout/read timeout messages.

Historical `Spread_Exception__c` records are not deleted when a later retry succeeds. Use the current `Spread_Document__c.Extraction_Status__c` and latest evidence records to determine current state.
