
CREATE TABLE public.learning_journey_feedback (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL,
  level TEXT NOT NULL CHECK (level IN ('beginner','intermediate','professional')),
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  learning_effectiveness SMALLINT NOT NULL CHECK (learning_effectiveness BETWEEN 1 AND 5),
  confidence_level SMALLINT NOT NULL CHECK (confidence_level BETWEEN 1 AND 5),
  business_relevance SMALLINT NOT NULL CHECK (business_relevance BETWEEN 1 AND 5),
  most_valuable_topic TEXT,
  comments TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role, level)
);

GRANT SELECT, INSERT ON public.learning_journey_feedback TO authenticated;
GRANT ALL ON public.learning_journey_feedback TO service_role;

ALTER TABLE public.learning_journey_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own feedback"
  ON public.learning_journey_feedback FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Users can submit own feedback"
  ON public.learning_journey_feedback FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE TRIGGER trg_ljf_updated_at
  BEFORE UPDATE ON public.learning_journey_feedback
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE OR REPLACE FUNCTION public.get_level_feedback_stats(_role TEXT)
RETURNS TABLE(
  level TEXT,
  avg_rating NUMERIC,
  total_responses BIGINT,
  positive_pct NUMERIC,
  confidence_improvement_pct NUMERIC,
  avg_effectiveness NUMERIC,
  avg_business_relevance NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    f.level,
    COALESCE(AVG(f.rating), 0)::NUMERIC AS avg_rating,
    COUNT(*)::BIGINT AS total_responses,
    COALESCE(
      (COUNT(*) FILTER (WHERE f.rating >= 4))::NUMERIC * 100
      / NULLIF(COUNT(*), 0), 0
    )::NUMERIC AS positive_pct,
    COALESCE(
      (COUNT(*) FILTER (WHERE f.confidence_level >= 4))::NUMERIC * 100
      / NULLIF(COUNT(*), 0), 0
    )::NUMERIC AS confidence_improvement_pct,
    COALESCE(AVG(f.learning_effectiveness), 0)::NUMERIC,
    COALESCE(AVG(f.business_relevance), 0)::NUMERIC
  FROM public.learning_journey_feedback f
  WHERE f.role = _role
  GROUP BY f.level;
$$;

GRANT EXECUTE ON FUNCTION public.get_level_feedback_stats(TEXT) TO authenticated, anon;
