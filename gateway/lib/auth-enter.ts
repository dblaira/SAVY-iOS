import type { AuthSession } from "./cognito-bridge.js";
import {
  cognitoEnabled,
  signIn,
  signUp,
} from "./cognito-bridge.js";
import {
  cognitoErrorMessage,
  isNotConfirmedError,
  isUsernameExistsError,
} from "./cognito-errors.js";

export type EnterAuthResult =
  | { ok: true; session: AuthSession; created: boolean }
  | { ok: false; status: number; message: string; error_code: string };

export async function enterWithEmailPassword(
  email: string,
  password: string
): Promise<EnterAuthResult> {
  if (!cognitoEnabled()) {
    return {
      ok: false,
      status: 503,
      message: "Sign-in is not configured on the gateway yet.",
      error_code: "auth_unavailable",
    };
  }

  try {
    const session = await signIn(email, password);
    return { ok: true, session, created: false };
  } catch (signInError) {
    if (isNotConfirmedError(signInError)) {
      return {
        ok: false,
        status: 403,
        message:
          "Your account exists but email is not confirmed yet. Check your inbox for the Cognito confirmation message.",
        error_code: "account_not_confirmed",
      };
    }
  }

  try {
    const session = await signUp(email, password);
    return { ok: true, session, created: true };
  } catch (signUpError) {
    if (isUsernameExistsError(signUpError)) {
      return {
        ok: false,
        status: 401,
        message: "That email and password did not match.",
        error_code: "invalid_credentials",
      };
    }

    if (isNotConfirmedError(signUpError)) {
      return {
        ok: false,
        status: 403,
        message:
          "Your account was created but is not active yet. Ask your admin to enable Cognito activation, or check your email for a confirmation message.",
        error_code: "account_not_confirmed",
      };
    }

    const message = cognitoErrorMessage(signUpError);
    const needsActivation = /not activated|AdminConfirmSignUp|not authorized/i.test(message);

    return {
      ok: false,
      status: needsActivation ? 503 : 400,
      message: needsActivation
        ? "Your account was created but Cognito has not activated it yet. Attach AmazonCognitoPowerUser to IAM user blair.ai.ops in AWS Console, then try Continue again."
        : message,
      error_code: needsActivation ? "activation_pending" : "sign_up_failed",
    };
  }
}
