CREATE TABLE "local_threads" (
	"thread_id" text PRIMARY KEY NOT NULL,
	"agent_id" text NOT NULL,
	"messages" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
