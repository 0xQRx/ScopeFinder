#!/bin/bash
# Generate Google Dorks with clickable links

MODULE_NAME="google_dorks_generator"
MODULE_DESC="Generate Google dork links"

module_init() {
    # Create output directory
    mkdir -p "${DIRS[DORKS]}"
}

module_run() {
    log_info "Generating Google dorks for: $DOMAIN"

    # Output file
    local output_file="${DIRS[DORKS]}/google_dorks.txt"

    # Clear previous results
    > "$output_file"

    # URL encode function for Google search queries
    url_encode() {
        local string="${1}"
        echo -n "$string" | sed 's/ /%20/g; s/|/%7C/g; s/:/%3A/g; s/"/%22/g; s/\[/%5B/g; s/\]/%5D/g; s/&/%26/g'
    }

    # Function to generate dork link
    generate_dork() {
        local title="$1"
        local query="$2"
        local encoded_query=$(url_encode "$query")
        echo "### $title" >> "$output_file"
        echo "$query" >> "$output_file"
        echo "https://www.google.com/search?q=$encoded_query" >> "$output_file"
        echo "" >> "$output_file"
    }

    # Replace example.com with actual domain in queries
    DOMAIN_ESCAPED="${DOMAIN//./\\.}"

    # Generate all dorks with clickable links

    generate_dork "Broad domain search (excluding common subdomains)" \
        "site:$DOMAIN -www -shop -share -ir -mfa"

    generate_dork "PHP files with parameters" \
        "site:$DOMAIN ext:php inurl:?"

    generate_dork "API Endpoints" \
        "site:$DOMAIN inurl:api | site:*/rest | site:*/v1 | site:*/v2 | site:*/v3"

    generate_dork "Juicy file extensions" \
        "site:$DOMAIN ext:log | ext:txt | ext:conf | ext:cnf | ext:ini | ext:env | ext:sh | ext:bak | ext:backup | ext:swp | ext:old | ext:~ | ext:git | ext:svn | ext:htpasswd | ext:htaccess | ext:json"

    generate_dork "Configuration and sensitive paths" \
        "inurl:conf | inurl:env | inurl:cgi | inurl:bin | inurl:etc | inurl:root | inurl:sql | inurl:backup | inurl:admin | inurl:php site:$DOMAIN"

    generate_dork "Server errors and exceptions" \
        "inurl:\"error\" | intitle:\"exception\" | intitle:\"failure\" | intitle:\"server at\" | inurl:exception | \"database error\" | \"SQL syntax\" | \"undefined index\" | \"unhandled exception\" | \"stack trace\" site:$DOMAIN"

    generate_dork "XSS prone parameters" \
        "inurl:q= | inurl:s= | inurl:search= | inurl:query= | inurl:keyword= | inurl:lang= inurl:& site:$DOMAIN"

    generate_dork "Open redirect prone parameters" \
        "inurl:url= | inurl:return= | inurl:next= | inurl:redirect= | inurl:redir= | inurl:ret= | inurl:r2= | inurl:page= inurl:& inurl:http site:$DOMAIN"

    generate_dork "SQL injection prone parameters" \
        "inurl:id= | inurl:pid= | inurl:category= | inurl:cat= | inurl:action= | inurl:sid= | inurl:dir= inurl:& site:$DOMAIN"

    generate_dork "SSRF prone parameters" \
        "inurl:http | inurl:url= | inurl:path= | inurl:dest= | inurl:html= | inurl:data= | inurl:domain= | inurl:page= inurl:& site:$DOMAIN"

    generate_dork "LFI prone parameters" \
        "inurl:include | inurl:dir | inurl:detail= | inurl:file= | inurl:folder= | inurl:inc= | inurl:locate= | inurl:doc= | inurl:conf= inurl:& site:$DOMAIN"

    generate_dork "RCE prone parameters" \
        "inurl:cmd | inurl:exec= | inurl:query= | inurl:code= | inurl:do= | inurl:run= | inurl:read= | inurl:ping= inurl:& site:$DOMAIN"

    generate_dork "File upload endpoints" \
        "site:$DOMAIN intext:\"choose file\" | intext:\"select file\" | intext:\"upload PDF\""

    generate_dork "API documentation" \
        "inurl:apidocs | inurl:api-docs | inurl:swagger | inurl:api-explorer | inurl:redoc | inurl:openapi | intitle:\"Swagger UI\" site:$DOMAIN"

    generate_dork "Login pages" \
        "inurl:login | inurl:signin | intitle:login | intitle:signin | inurl:secure site:$DOMAIN"

    generate_dork "Test environments" \
        "inurl:test | inurl:env | inurl:dev | inurl:staging | inurl:sandbox | inurl:debug | inurl:temp | inurl:internal | inurl:demo site:$DOMAIN"

    generate_dork "Sensitive documents" \
        "site:$DOMAIN ext:txt | ext:pdf | ext:xml | ext:xls | ext:xlsx | ext:ppt | ext:pptx | ext:doc | ext:docx intext:\"confidential\" | intext:\"Not for Public Release\" | intext:\"internal use only\" | intext:\"do not distribute\""

    generate_dork "Sensitive parameters (PII)" \
        "inurl:email= | inurl:phone= | inurl:name= | inurl:user= inurl:& site:$DOMAIN"

    generate_dork "Adobe Experience Manager (AEM)" \
        "inurl:/content/usergenerated | inurl:/content/dam | inurl:/jcr:content | inurl:/libs/granite | inurl:/etc/clientlibs | inurl:/content/geometrixx | inurl:/bin/wcm | inurl:/crx/de site:$DOMAIN"

    generate_dork "Disclosed vulnerabilities on OpenBugBounty" \
        "site:openbugbounty.org inurl:reports intext:\"$DOMAIN\""

    generate_dork "Google Groups discussions" \
        "site:groups.google.com \"$DOMAIN\""

    # Code leak sites
    generate_dork "Pastebin code leaks" \
        "site:pastebin.com \"$DOMAIN\""

    generate_dork "JSFiddle code leaks" \
        "site:jsfiddle.net \"$DOMAIN\""

    generate_dork "CodeBeautify code leaks" \
        "site:codebeautify.org \"$DOMAIN\""

    generate_dork "CodePen code leaks" \
        "site:codepen.io \"$DOMAIN\""

    # Cloud storage
    generate_dork "AWS S3 buckets" \
        "site:s3.amazonaws.com \"$DOMAIN\""

    generate_dork "Azure blob storage" \
        "site:blob.core.windows.net \"$DOMAIN\""

    generate_dork "Google APIs storage" \
        "site:googleapis.com \"$DOMAIN\""

    generate_dork "Google Drive files" \
        "site:drive.google.com \"$DOMAIN\""

    generate_dork "Google Docs" \
        "site:docs.google.com inurl:\"/d/\" \"$DOMAIN\""

    generate_dork "Azure DevOps" \
        "site:dev.azure.com \"$DOMAIN\""

    generate_dork "OneDrive files" \
        "site:onedrive.live.com \"$DOMAIN\""

    generate_dork "DigitalOcean Spaces" \
        "site:digitaloceanspaces.com \"$DOMAIN\""

    generate_dork "SharePoint documents" \
        "site:sharepoint.com \"$DOMAIN\""

    generate_dork "Dropbox shared files" \
        "site:dropbox.com/s \"$DOMAIN\""

    generate_dork "JFrog Artifactory" \
        "site:jfrog.io \"$DOMAIN\""

    generate_dork "Firebase databases" \
        "site:firebaseio.com \"$DOMAIN\""

    # WordPress specific
    generate_dork "WordPress admin AJAX" \
        "site:$DOMAIN inurl:/wp-admin/admin-ajax.php"

    generate_dork "WordPress content uploads" \
        "site:$DOMAIN inurl:/wp-content/uploads/"

    # Count total dorks generated
    local dork_count=$(grep -c "^###" "$output_file")
    log_info "Generated $dork_count Google dork queries"
    log_info "Results saved to: $output_file"

    return 0
}

module_cleanup() {
    log_debug "Cleaning up Google dorks generator artifacts"
}