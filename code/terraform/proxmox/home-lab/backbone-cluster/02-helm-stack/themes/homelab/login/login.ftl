<#-- Homelab custom login page (Keycloak, homelab realm). Self-contained: all
     markup + CSS inline, no external stylesheet/font. Background photo is the
     only remote asset (Unsplash CDN) with a dark gradient fallback beneath. -->
<!DOCTYPE html>
<html lang="${(locale.currentLanguageTag)!'en'}">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/>
  <meta name="robots" content="noindex, nofollow"/>
  <title>${msg("loginTitle",(realm.displayName!'Homelab'))}</title>
  <style>
    :root{
      --txt:#e7e9ee; --muted:#9aa1ad; --field:rgba(255,255,255,.045);
      --field-brd:rgba(255,255,255,.12); --accent:#6366f1; --accent2:#8b5cf6;
      --danger:#f87171; --radius:16px;
    }
    *{box-sizing:border-box}
    html,body{height:100%}
    body{margin:0;color:var(--txt);background:#08090c;
      font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,Helvetica,Arial,sans-serif;
      -webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}
    .bg{position:fixed;inset:0;z-index:-2;background:#08090c;
      background-image:url("https://images.unsplash.com/photo-1638184984605-af1f05249a56?ixlib=rb-4.1.0&q=80&w=2400&auto=format&fit=crop");
      background-size:cover;background-position:center}
    .bg::after{content:"";position:absolute;inset:0;background:
      radial-gradient(1100px 760px at 28% 18%, rgba(99,102,241,.14), transparent 60%),
      linear-gradient(180deg, rgba(6,7,10,.52) 0%, rgba(6,7,10,.80) 58%, rgba(6,7,10,.94) 100%)}
    .wrap{min-height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:34px 20px}
    .brand{display:flex;flex-direction:column;align-items:center;margin-bottom:26px;user-select:none}
    .brand .mark{font-size:13px;font-weight:600;letter-spacing:.42em;color:#fff;display:flex;align-items:center}
    .brand .dot{width:7px;height:7px;border-radius:50%;margin-right:12px;
      background:linear-gradient(135deg,var(--accent),var(--accent2));box-shadow:0 0 16px 2px rgba(124,92,246,.6)}
    .brand .sub{margin-top:9px;font-size:12px;color:var(--muted);letter-spacing:.02em}
    .card{width:100%;max-width:400px;padding:30px 28px 26px;border-radius:var(--radius);
      background:rgba(18,20,27,.72);border:1px solid rgba(255,255,255,.08);
      backdrop-filter:blur(22px) saturate(140%);-webkit-backdrop-filter:blur(22px) saturate(140%);
      box-shadow:0 24px 70px -20px rgba(0,0,0,.72), inset 0 1px 0 rgba(255,255,255,.05)}
    .title{margin:0 0 4px;font-size:19px;font-weight:650;letter-spacing:-.01em}
    .subtitle{margin:0 0 22px;font-size:13px;color:var(--muted)}
    .field{margin-bottom:15px}
    .field label{display:block;font-size:12px;color:var(--muted);margin:0 0 7px;font-weight:500}
    .ipt{position:relative;display:flex;align-items:center}
    .ipt input{width:100%;height:44px;padding:0 14px;color:var(--txt);font-size:14px;
      background:var(--field);border:1px solid var(--field-brd);border-radius:10px;outline:none;
      transition:border-color .15s,box-shadow .15s,background .15s}
    .ipt input::placeholder{color:#6b7280}
    .ipt input:focus{border-color:var(--accent);background:rgba(99,102,241,.06);box-shadow:0 0 0 3px rgba(99,102,241,.18)}
    .ipt.has-reveal input{padding-right:44px}
    .reveal{position:absolute;right:6px;height:32px;width:32px;display:grid;place-items:center;
      border:0;background:transparent;color:var(--muted);cursor:pointer;border-radius:8px}
    .reveal:hover{color:var(--txt);background:rgba(255,255,255,.06)}
    .row{display:flex;align-items:center;justify-content:space-between;min-height:20px;margin:4px 0 20px}
    .remember{display:flex;align-items:center;gap:8px;font-size:12.5px;color:var(--muted);cursor:pointer;user-select:none}
    .remember input{accent-color:var(--accent);width:15px;height:15px}
    .link{color:#a5b4fc;font-size:12.5px;text-decoration:none}
    .link:hover{color:#c7d2fe;text-decoration:underline}
    .btn{width:100%;height:46px;border:0;border-radius:11px;color:#fff;font-size:14.5px;font-weight:600;cursor:pointer;
      background:linear-gradient(135deg,var(--accent),var(--accent2));
      box-shadow:0 10px 26px -10px rgba(99,102,241,.8);transition:transform .06s,box-shadow .2s,filter .2s}
    .btn:hover{filter:brightness(1.07);box-shadow:0 14px 30px -10px rgba(99,102,241,.9)}
    .btn:active{transform:translateY(1px)}
    .divider{display:flex;align-items:center;gap:12px;margin:22px 0 16px;color:#6b7280;
      font-size:11px;letter-spacing:.08em;text-transform:uppercase}
    .divider::before,.divider::after{content:"";height:1px;flex:1;
      background:linear-gradient(90deg,transparent,rgba(255,255,255,.13),transparent)}
    .social{display:flex;flex-direction:column;gap:10px}
    .social a{display:flex;align-items:center;justify-content:center;gap:10px;height:44px;border-radius:10px;
      text-decoration:none;color:var(--txt);font-size:14px;font-weight:500;
      background:rgba(255,255,255,.045);border:1px solid var(--field-brd);
      transition:background .15s,border-color .15s,transform .06s}
    .social a:hover{background:rgba(255,255,255,.085);border-color:rgba(255,255,255,.22)}
    .social a:active{transform:translateY(1px)}
    .social svg{width:18px;height:18px;fill:currentColor;flex:0 0 auto}
    .alert{display:flex;gap:10px;padding:11px 13px;border-radius:10px;font-size:13px;margin-bottom:18px;line-height:1.45}
    .alert-error{background:rgba(248,113,113,.1);border:1px solid rgba(248,113,113,.3);color:#fecaca}
    .alert-warning{background:rgba(251,191,36,.1);border:1px solid rgba(251,191,36,.3);color:#fde68a}
    .alert-success{background:rgba(52,211,153,.1);border:1px solid rgba(52,211,153,.3);color:#a7f3d0}
    .alert-info{background:rgba(96,165,250,.1);border:1px solid rgba(96,165,250,.3);color:#bfdbfe}
    .field-error{color:var(--danger);font-size:12px;margin-top:6px}
    .foot{margin-top:22px;text-align:center;font-size:11.5px;color:#5b6472}
    .foot a{color:#8891a0;text-decoration:none}.foot a:hover{color:#aab2c0}
    .page-foot{margin-top:20px;font-size:11px;color:#4b5361;letter-spacing:.02em}
    @media (max-width:440px){.card{padding:24px 20px}}
  </style>
</head>
<body>
  <div class="bg"></div>
  <div class="wrap">
    <div class="brand">
      <div class="mark"><span class="dot"></span>${(realm.displayName!'HOMELAB')?upper_case}</div>
      <div class="sub">Secure access to lab services</div>
    </div>

    <div class="card">
      <#if message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
        <div class="alert alert-${message.type}">${kcSanitize(message.summary)?no_esc}</div>
      </#if>

      <h1 class="title">${msg("loginAccountTitle")}</h1>
      <p class="subtitle">Sign in to continue to ${(client.name!client.clientId!'your account')}</p>

      <#if realm.password>
      <form id="kc-form-login" action="${url.loginAction}" method="post" autocomplete="off">
        <div class="field">
          <label for="username"><#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}<#else>${msg("email")}</#if></label>
          <div class="ipt">
            <input id="username" name="username" type="text" tabindex="1" autofocus autocomplete="username"
                   value="${(login.username!'')}" <#if usernameEditDisabled??>disabled</#if>
                   placeholder="<#if !realm.loginWithEmailAllowed>${msg('username')}<#else>${msg('usernameOrEmail')}</#if>"/>
          </div>
          <#if messagesPerField.existsError('username')>
            <div class="field-error">${kcSanitize(messagesPerField.get('username'))?no_esc}</div>
          </#if>
        </div>

        <div class="field">
          <label for="password">${msg("password")}</label>
          <div class="ipt has-reveal">
            <input id="password" name="password" type="password" tabindex="2" autocomplete="current-password" placeholder="••••••••"/>
            <button type="button" class="reveal" tabindex="-1" aria-label="Show password"
                    onclick="var p=document.getElementById('password');p.type=(p.type==='password')?'text':'password';">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7z"/><circle cx="12" cy="12" r="3"/></svg>
            </button>
          </div>
          <#if messagesPerField.existsError('password')>
            <div class="field-error">${kcSanitize(messagesPerField.get('password'))?no_esc}</div>
          </#if>
        </div>

        <div class="row">
          <#if realm.rememberMe && !usernameEditDisabled??>
            <label class="remember"><input name="rememberMe" type="checkbox" tabindex="3" <#if login.rememberMe??>checked</#if>/>${msg("rememberMe")}</label>
          <#else>
            <span></span>
          </#if>
          <#if realm.resetPasswordAllowed>
            <a class="link" href="${url.loginResetCredentialsUrl}" tabindex="6">${msg("doForgotPassword")}</a>
          </#if>
        </div>

        <input type="hidden" id="id-hidden-input" name="credentialId" <#if auth?? && auth.selectedCredential?has_content>value="${auth.selectedCredential}"</#if>/>
        <button class="btn" name="login" id="kc-login" type="submit" tabindex="4">${msg("doLogIn")}</button>
      </form>
      </#if>

      <#if realm.password && social.providers??>
        <div class="divider">or continue with</div>
        <div class="social">
          <#list social.providers as p>
            <a id="social-${p.alias}" href="${p.loginUrl}">
              <#if p.alias == 'github'>
                <svg viewBox="0 0 24 24"><path d="M12 .5C5.7.5.5 5.7.5 12c0 5.1 3.3 9.4 7.9 10.9.6.1.8-.2.8-.5v-1.8c-3.2.7-3.9-1.5-3.9-1.5-.5-1.3-1.3-1.7-1.3-1.7-1.1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.7-1.6-2.6-.3-5.3-1.3-5.3-5.7 0-1.3.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.1 0 0 1-.3 3.3 1.2a11.5 11.5 0 016 0c2.3-1.5 3.3-1.2 3.3-1.2.6 1.6.2 2.8.1 3.1.8.8 1.2 1.8 1.2 3.1 0 4.4-2.7 5.4-5.3 5.7.4.4.8 1.1.8 2.2v3.3c0 .3.2.6.8.5 4.6-1.5 7.9-5.8 7.9-10.9C23.5 5.7 18.3.5 12 .5z"/></svg>
              </#if>
              <span>Continue with ${(p.displayName!p.alias)}</span>
            </a>
          </#list>
        </div>
      </#if>

      <#if realm.password && realm.registrationAllowed && !registrationDisabled??>
        <div class="foot">${msg("noAccount")} <a href="${url.registrationUrl}">${msg("doRegister")}</a></div>
      </#if>
    </div>

    <div class="page-foot">${(realm.displayName!'Homelab')} &middot; protected by Keycloak</div>
  </div>
</body>
</html>
