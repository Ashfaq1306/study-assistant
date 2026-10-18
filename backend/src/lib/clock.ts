/** Injected source of "now" so expiry rules can be tested without waiting. */
export type Clock = () => Date;

export const systemClock: Clock = () => new Date();
