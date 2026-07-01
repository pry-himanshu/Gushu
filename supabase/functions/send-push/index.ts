import "@supabase/functions-js/edge-runtime.d.ts";

function base64url(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

async function getAccessToken() {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY");

  if (!projectId || !clientEmail || !privateKey) {
    throw new Error(
      `Missing Firebase credentials. Required: FIREBASE_PROJECT_ID (${projectId ? "✓" : "✗"}), FIREBASE_CLIENT_EMAIL (${clientEmail ? "✓" : "✗"}), FIREBASE_PRIVATE_KEY (${privateKey ? "✓" : "✗"})`
    );
  }

  const now = Math.floor(Date.now() / 1000);

  const header = {
    alg: "RS256",
    typ: "JWT",
  };

  const payload = {
    iss: clientEmail,
    sub: clientEmail,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };

  const encodedHeader = btoa(JSON.stringify(header))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");

  const encodedPayload = btoa(JSON.stringify(payload))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");

  const unsignedJwt = `${encodedHeader}.${encodedPayload}`;

  const pemContents = privateKey
    .replace(/\\n/g, "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const binaryDer = Uint8Array.from(
    atob(pemContents),
    c => c.charCodeAt(0)
  );

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsignedJwt)
  );

  const signedJwt =
    `${unsignedJwt}.${base64url(new Uint8Array(signature))}`;

  const tokenResponse = await fetch(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: {
        "Content-Type":
          "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        grant_type:
          "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: signedJwt,
      }),
    }
  );

  const tokenData = await tokenResponse.json();
  
  if (!tokenData.access_token) {
    throw new Error(`Failed to get FCM access token: ${JSON.stringify(tokenData)}`);
  }

  return {
    accessToken: tokenData.access_token,
    projectId,
  };
}

Deno.serve(async (req) => {
  try {
    const { token, title, body, data } = await req.json();

    if (!token) {
      return Response.json(
        { success: false, error: "Token is required" },
        { status: 400 }
      );
    }

    const { accessToken, projectId } =
      await getAccessToken();

    // Build the FCM message
    const messageBody: any = {
      message: {
        token,
        notification: {
          title: title || "Gushu",
          body: body || "New message",
        },
      },
    };

    // Add data field if provided
    if (data && typeof data === "object") {
      messageBody.message.data = data;
    }

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(messageBody),
      }
    );

    const result = await response.json();

    if (!response.ok) {
      console.error("FCM Error:", result);
    }

    return Response.json({
      success: response.ok,
      result,
    });
  } catch (error) {
    console.error("Send-push error:", error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    return Response.json(
      {
        success: false,
        error: errorMessage,
      },
      { status: 500 }
    );
  }
});