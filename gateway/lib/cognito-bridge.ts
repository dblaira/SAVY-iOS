import {
  CognitoIdentityProviderClient,
  GlobalSignOutCommand,
  InitiateAuthCommand,
  SignUpCommand,
  type InitiateAuthCommandOutput,
} from "@aws-sdk/client-cognito-identity-provider";

export type AuthUser = {
  id: string;
  email: string | null;
};

export type AuthSession = {
  access_token: string;
  refresh_token: string;
  token_type: string;
  expires_in: number;
  user: AuthUser;
};

function cognitoClient() {
  const region = process.env.COGNITO_REGION ?? process.env.AWS_REGION ?? "us-west-2";
  return new CognitoIdentityProviderClient({ region });
}

function poolConfig() {
  const userPoolId = process.env.COGNITO_USER_POOL_ID;
  const clientId = process.env.COGNITO_CLIENT_ID;

  if (!userPoolId || !clientId) {
    throw new Error("COGNITO_USER_POOL_ID and COGNITO_CLIENT_ID required");
  }

  return { userPoolId, clientId };
}

function decodeJwtPayload(token: string): Record<string, unknown> {
  const segment = token.split(".")[1];
  if (!segment) return {};
  const json = Buffer.from(segment, "base64url").toString("utf8");
  return JSON.parse(json) as Record<string, unknown>;
}

function sessionFromAuthResult(
  result: InitiateAuthCommandOutput["AuthenticationResult"],
  fallbackEmail?: string
): AuthSession {
  if (!result?.AccessToken || !result.RefreshToken) {
    throw new Error("Cognito did not return session tokens");
  }

  const payload = decodeJwtPayload(result.AccessToken);
  const sub = String(payload.sub ?? "");
  const email =
    typeof payload.email === "string"
      ? payload.email
      : fallbackEmail ?? null;

  return {
    access_token: result.AccessToken,
    refresh_token: result.RefreshToken,
    token_type: "bearer",
    expires_in: result.ExpiresIn ?? 3600,
    user: { id: sub, email },
  };
}

export async function signIn(email: string, password: string): Promise<AuthSession> {
  const { clientId } = poolConfig();
  const client = cognitoClient();

  const response = await client.send(
    new InitiateAuthCommand({
      ClientId: clientId,
      AuthFlow: "USER_PASSWORD_AUTH",
      AuthParameters: {
        USERNAME: email,
        PASSWORD: password,
      },
    })
  );

  return sessionFromAuthResult(response.AuthenticationResult, email);
}

export async function signUp(email: string, password: string): Promise<AuthSession> {
  const { clientId } = poolConfig();
  const client = cognitoClient();

  await client.send(
    new SignUpCommand({
      ClientId: clientId,
      Username: email,
      Password: password,
      UserAttributes: [{ Name: "email", Value: email }],
    })
  );

  return signIn(email, password);
}

export async function signOut(accessToken: string): Promise<void> {
  const client = cognitoClient();
  await client.send(
    new GlobalSignOutCommand({
      AccessToken: accessToken,
    })
  );
}

export function cognitoEnabled(): boolean {
  return Boolean(process.env.COGNITO_USER_POOL_ID && process.env.COGNITO_CLIENT_ID);
}
