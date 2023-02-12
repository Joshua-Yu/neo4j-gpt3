

// Embedding


// 1) api
:param openai_api_url=>'https://api.openai.com/v1/embeddings';
:param openai_api_header_content_type=>"application/json";
:param openai_api_header_auth=>"Bearer " + '***OPENAI-KEY***';
:param openai_embedding_model=>"text-embedding-ada-002";

// 2) Get embeddings for all Title text

:auto MATCH (t:Title)
WHERE t.embedding IS NULL
CALL {
    WITH t 
    WITH t,
        apoc.convert.toJson(
            {
                model: $openai_embedding_model,
                input: t.text
            }
        ) AS payload
    CALL apoc.load.jsonParams(
        $openai_api_url,
        {
            `Content-Type`:$openai_api_header_content_type,
            Authorization: $openai_api_header_auth
        },
        payload, null,
        {}
    ) YIELD value
    SET t.embedding = value.data[0].embedding
} IN TRANSACTIONS OF 20 ROWS
RETURN count(t) AS count;

// 
// 3) Run search
//
:param search=>'unsupervised learning of graph embedding';

WITH apoc.convert.toJson(
        {
            model: $openai_embedding_model,
            input: $search
        }
     ) AS payload
CALL apoc.load.jsonParams(
    $openai_api_url,
    {
        `Content-Type`:$openai_api_header_content_type,
        Authorization: $openai_api_header_auth
    },
    payload, null,
    {}
) YIELD value
WITH value.data[0].embedding AS searchEmb
MATCH (t:Title)
WHERE NOT t.embedding IS NULL
RETURN t.text AS title, gds.similarity.cosine(t.embedding, searchEmb) AS similarity
ORDER BY similarity DESC LIMIT 10;


