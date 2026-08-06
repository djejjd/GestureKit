export type E2EPageCommand = {
  token: string;
  gestureSessionId: string;
  operationId: string;
  scenario: "success" | "leaseExpiry" | "providerUnavailable" | "resultUnknown";
};

export function createE2EControl(input: {
  token: string | null;
  allowedOrigin: string | null;
  dispatch: (command: E2EPageCommand) => Promise<{ status: string }>;
}): { handle(origin: string, command: E2EPageCommand): Promise<{ status: string }> } {
  const { token, allowedOrigin, dispatch } = input;

  return {
    async handle(origin: string, command: E2EPageCommand): Promise<{ status: string }> {
      if (!token || !allowedOrigin) {
        return { status: "e2e_unavailable" };
      }
      if (origin !== allowedOrigin) {
        return { status: "e2e_origin_rejected" };
      }
      if (command.token !== token) {
        return { status: "e2e_token_rejected" };
      }
      return dispatch(command);
    }
  };
}
