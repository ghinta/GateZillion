--!strict
-- Shared domain types. Coordinates: `z` is the distance along the track from the start line,
-- `x` the lateral offset from the track centre (negative = left, positive = right).

export type GateOp = "add" | "subtract" | "multiply"

export type Gate = {
	id: string,
	z: number,
	xMin: number,
	xMax: number,
	op: GateOp,
	value: number,
}

export type Obstacle = {
	id: string,
	z: number,
	xMin: number,
	xMax: number,
	damage: number,
}

-- Enemies always span the full track width and cannot be avoided.
export type Enemy = {
	id: string,
	z: number,
	count: number,
}

export type Level = {
	id: number,
	name: string,
	length: number,
	startCount: number,
	minFinishCount: number,
	gates: { Gate },
	obstacles: { Obstacle },
	enemies: { Enemy },
}

export type Phase = "Lobby" | "Loading" | "Running" | "Completed" | "Failed" | "Results"

export type RunResult = "Completed" | "Failed"

export type HitKind = "gate" | "obstacle" | "enemy"

-- One level element crossed by the group during a simulation step.
export type Hit = {
	kind: HitKind,
	id: string,
	z: number,
	gate: Gate?,
	obstacle: Obstacle?,
	enemy: Enemy?,
}

return {}
