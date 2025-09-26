#!/bin/bash
set -e

# Apply proxy support patches to the codebase
echo "Applying proxy support patches..."

# 1. Add proxy configuration to config_types.rs
patch -p1 << 'EOF'
--- a/codex-rs/core/src/config_types.rs
+++ b/codex-rs/core/src/config_types.rs
@@ -1,5 +1,6 @@
 //! Types used to define the fields of [`crate::config::Config`].
 
+use std::collections::HashMap;
 use std::collections::HashMap;
 use std::path::PathBuf;
 use std::time::Duration;
@@ -8,6 +9,30 @@ use wildmatch::WildMatchPattern;
 use serde::Deserialize;
 use serde::Deserializer;
 use serde::Serialize;
+use serde::de::Error as SerdeError;
+
+#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
+pub struct ProxyConfig {
+    /// HTTP proxy URL
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub http: Option<String>,
+    
+    /// HTTPS proxy URL  
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub https: Option<String>,
+    
+    /// SOCKS proxy URL
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub socks: Option<String>,
+    
+    /// Proxy authentication username
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub username: Option<String>,
+    
+    /// Proxy authentication password
+    #[serde(default, skip_serializing_if = "Option::is_none")]
+    pub password: Option<String>,
+}
 
 #[derive(Serialize, Debug, Clone, PartialEq)]
 pub struct McpServerConfig {
EOF

# 2. Modify Config struct to include proxy settings
patch -p1 << 'EOF'
--- a/codex-rs/core/src/config.rs
+++ b/codex-rs/core/src/config.rs
@@ -4,6 +4,7 @@ use crate::config_types::History;
 use crate::config_types::McpServerConfig;
 use crate::config_types::Notifications;
 use crate::config_types::ReasoningSummaryFormat;
+use crate::config_types::ProxyConfig;
 use crate::config_types::SandboxWorkspaceWrite;
 use crate::config_types::ShellEnvironmentPolicy;
 use crate::config_types::ShellEnvironmentPolicyToml;
@@ -100,6 +101,9 @@ pub struct Config {
     /// Optional external notifier command. When set, Codex will spawn this
     /// program after each completed *turn* (i.e. when the agent finishes
     pub notifier: Option<String>,
+
+    /// Proxy configuration for HTTP/HTTPS/SOCKS requests
+    pub proxy: Option<ProxyConfig>,
 }
 
 impl Config {
EOF

# 3. Update default_client.rs to support proxy configuration
patch -p1 << 'EOF'
--- a/codex-rs/core/src/default_client.rs
+++ b/codex-rs/core/src/default_client.rs
@@ -1,5 +1,6 @@
 use crate::spawn::CODEX_SANDBOX_ENV_VAR;
 use reqwest::header::HeaderValue;
+use reqwest::Proxy;
 use std::sync::LazyLock;
 use std::sync::Mutex;
 
@@ -108,6 +109,7 @@ pub fn get_codex_user_agent() -> String {
 /// Create a reqwest client with default `originator` and `User-Agent` headers set.
 pub fn create_client() -> reqwest::Client {
     use reqwest::header::HeaderMap;
+    use crate::config::Config;
 
     let mut headers = HeaderMap::new();
     headers.insert("originator", ORIGINATOR.header_value.clone());
@@ -119,6 +121,36 @@ pub fn create_client() -> reqwest::Client {
         .user_agent(ua)
         .default_headers(headers);
     
+    // Add proxy support from configuration
+    if let Some(config) = Config::current() {
+        if let Some(proxy_config) = &config.proxy {
+            // Configure HTTP proxy
+            if let Some(http_proxy) = &proxy_config.http {
+                builder = builder.proxy(Proxy::http(http_proxy).unwrap());
+            }
+            
+            // Configure HTTPS proxy
+            if let Some(https_proxy) = &proxy_config.https {
+                builder = builder.proxy(Proxy::https(https_proxy).unwrap());
+            }
+            
+            // Configure SOCKS proxy
+            if let Some(socks_proxy) = &proxy_config.socks {
+                builder = builder.proxy(Proxy::socks(socks_proxy).unwrap());
+            }
+        }
+    }
+    
+    // Fall back to environment variables
+    if std::env::var("HTTP_PROXY").is_ok() {
+        builder = builder.proxy(Proxy::custom(std::env::var("HTTP_PROXY").unwrap()));
+    }
+    if std::env::var("HTTPS_PROXY").is_ok() {
+        builder = builder.proxy(Proxy::custom(std::env::var("HTTPS_PROXY").unwrap()));
+    }
+    if std::env::var("SOCKS_PROXY").is_ok() {
+        builder = builder.proxy(Proxy::custom(std::env::var("SOCKS_PROXY").unwrap()));
+    }
+    
     if is_sandboxed() {
         builder = builder.no_proxy();
     }
EOF

# 4. Update test initializers to include proxy: None
patch -p1 << 'EOF'
--- a/codex-rs/core/src/config.rs
+++ b/codex-rs/core/src/config.rs
@@ -1642,6 +1642,7 @@ mod tests {
                 user_instructions: None,
                 notify: None,
                 cwd: fixture.cwd(),
+                proxy: None,
                 mcp_servers: HashMap::new(),
                 model_providers: fixture.model_provider_map.clone(),
                 project_doc_max_bytes: PROJECT_DOC_MAX_BYTES,
@@ -1700,6 +1701,7 @@ mod tests {
                 shell_environment_policy: ShellEnvironmentPolicy::default(),
                 user_instructions: None,
                 notify: None,
+                proxy: None,
                 cwd: fixture.cwd(),
                 mcp_servers: HashMap::new(),
                 model_providers: fixture.model_provider_map.clone(),
@@ -1773,6 +1775,7 @@ mod tests {
                 shell_environment_policy: ShellEnvironmentPolicy::default(),
                 user_instructions: None,
                 notify: None,
+                proxy: None,
                 cwd: fixture.cwd(),
                 mcp_servers: HashMap::new(),
                 model_providers: fixture.model_provider_map.clone(),
@@ -1832,6 +1835,7 @@ mod tests {
                 shell_environment_policy: ShellEnvironmentPolicy::default(),
                 user_instructions: None,
                 notify: None,
+                proxy: None,
                 cwd: fixture.cwd(),
                 mcp_servers: HashMap::new(),
                 model_providers: fixture.model_provider_map.clone(),
EOF

echo "Proxy patches applied successfully!"