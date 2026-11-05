interface CommonStellarTelFields {
  timestamp: string,
  event: string
}

export const LegalStateEnum = {
  "Clean": 1,
  "IllegalCargo": 2,
  "Speeding": 3,
  "Wanted": 4,
  "Hostile": 5,
  "PassengerWanted": 6,
  "Warrant": 7,
  "Allied": 8,
  "Thargoid": 9
} as const;


export interface StatusJournal extends CommonStellarTelFields {
  // Assert this is an integer (32 bits)
  Flags: number,
  // Assert this is an integer (32 bits)
  Flags2: number,
  LegalState: string,
  Balance: number,
  Cargo: number
}

export interface StatusPayload {
  cargo: number,
  mass_locked: number,
  low_fuel: number,
  overheating: number,
  in_danger: number,
  being_interdicted: number,
  legal_state: string,
};
