import { createHmac } from "node:crypto";
import {
  AdminConfirmSignUpCommand,
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
  const userPoolId =
    process.env.COGNITO_USER_POOL_ID ?? "us-west-2_sqayHoHrK";
  const clientId =
    process.env.COGNITO_CLIENT_ID ?? "omkdcfdi0rsems3fmc7r5r797";
  const clientSecret = process.env.COGNITO_CLIENT_SECRET;

  if (!userPoolId || !clientId) {
    throw new Error("COGNITO_USER_POOL_ID and COGNITO_CLIENT_ID required");
  }

  return { userPoolId, clientId, clientSecret };
}

function secretHash(username: string, clientId: string, clientSecret: string): string {
  return createHmac("sha256", clientSecret)
    .update(`${username}${clientId}`)
    .digest("base64");
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

function authParameters(email: string, password: string): Record<string, string> {
  const { clientId, clientSecret } = poolConfig();
  const params: Record<string, string> = {
    USERNAME: email,
    PASSWORD: password,
  };

  if (clientSecret) {
    params.SECRET_HASH = secretHash(email, clientId, clientSecret);
  }

  return params;
}

export async function signIn(email: string, password: string): Promise<AuthSession> {
  const { clientId } = poolConfig();
  const client = cognitoClient();

  const response = await client.send(
    new InitiateAuthCommand({
      ClientId: clientId,
      AuthFlow: "USER_PASSWORD_AUTH",
      AuthParameters: authParameters(email, password),
    })
  );

  return sessionFromAuthResult(response.AuthenticationResult, email);
}

export async function signUp(email: string, password: string): Promise<AuthSession> {
  const { clientId, clientSecret } = poolConfig();
  const client = cognitoClient();

  const signUpInput: ConstructorParameters<typeof SignUpCommand>[0] = {
    ClientId: clientId,
    Username: email,
    Password: password,
    UserAttributes: [{ Name: "email", Value: email }],
  };

  if (clientSecret) {
    signUpInput.SecretHash = secretHash(email, clientId, clientSecret);
  }

  await client.send(new SignUpCommand(signUpInput));

  try {
    return await signIn(email, password);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!/not confirmed/i.test(message)) throw error;

    const { userPoolId } = poolConfig();
    try {
      await client.send(
        new AdminConfirmSignUpCommand({
          UserPoolId: userPoolId,
          Username: email,
        })
      );
      return signIn(email, password);
    } catch {
      throw new Error(
        "Account created but not confirmed yet. Check your email for a confirmation code, then sign in."
      );
    }
  }
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
  const { userPoolId, clientId } = poolConfig();
  return Boolean(userPoolId && clientId);
}
