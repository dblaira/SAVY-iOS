/**
 * Cognito Pre Sign-up trigger — auto-confirms new users so sign-up
 * immediately returns a session (no email confirmation step).
 *
 * Deploy: scripts/cognito/deploy-pre-signup-lambda.sh
 */
export const handler = async (event) => {
  event.response.autoConfirmUser = true;
  event.response.autoVerifyEmail = true;
  return event;
};
