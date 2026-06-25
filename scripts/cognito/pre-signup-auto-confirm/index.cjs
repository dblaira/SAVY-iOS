/**
 * Cognito Pre Sign-up trigger (CommonJS — use this in AWS Console inline editor).
 */
exports.handler = async (event) => {
  event.response.autoConfirmUser = true;
  event.response.autoVerifyEmail = true;
  return event;
};
