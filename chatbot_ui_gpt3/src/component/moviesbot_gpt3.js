
import React, { Component } from 'react';
import PropTypes from 'prop-types';
import { Loading } from 'react-simple-chatbot';

import Speech from 'speak-tts'


const CONFIDENTIAL = "[CONFIDENTIAL]";
const speech = new Speech()
require('dotenv').config()


const { Configuration, OpenAIApi } = require("openai");
const neo4j = require('neo4j-driver')

const driver = neo4j.driver(process.env.REACT_APP_NEO4JURI, neo4j.auth.basic(process.env.REACT_APP_NEO4JUSER, process.env.REACT_APP_NEO4JPASSWORD))

const session = driver.session({database:process.env.REACT_APP_NEO4JDATABASE || 'neo4j'})

const configuration = new Configuration({
  apiKey: process.env.REACT_APP_OPENAI_API_KEY
});
const openai = new OpenAIApi(configuration);


speech.init({
  'volume': 1,
  'lang': 'en-GB',
  'rate': 1,
  'pitch': 1,
  'voice': 'Google UK English Male',
  'splitSentences': true,
  'listeners': {
    'onvoiceschanged': (voices) => {
      console.log("Event voiceschanged", voices)
    }
  }
})

class MoviesBot extends Component {
  constructor(props) {
    super(props);

    this.state = {
      loading: true,
      result: ''
    };

    this.triggetNext = this.triggetNext.bind(this);
  }

  callMoviesBot() {

    const self = this;
    const { steps } = this.props;
    const search = steps.user.value;

    async function callAsync() {
      let training = `
#When was movie The Matrix released?
MATCH (m:Movie) WHERE m.title =~ '(?i)The Matrix' RETURN m.released AS year;

#What is the tagline of movie The Matrix?
MATCH (m:Movie) WHERE m.title =~ '(?i)The Matrix' RETURN m.tagline AS tagline;

#When was keanu reeves born?
MATCH (p:Person) WHERE p.name =~ '(?i)keanu reeves' RETURN p.born AS year;

#What are the 3 most recent movies that Keanu Reeves has acted in?
MATCH (p:Person) -[r:ACTED_IN]-> (m:Movie)
WHERE p.name =~ '(?i)Keanu Reeves'
RETURN m.title AS title, m.released AS year 
ORDER BY m.released DESC
LIMIT 3;

#Who has acted the role Neo in movie The Matrix?
MATCH (p0:Person) -[r:ACTED_IN]-> (m:Movie) 
WHERE m.title =~ '(?i)The Matrix' 
WITH p0.name AS who, r.roles AS roles
UNWIND roles AS role
WITH who WHERE role =~ '(?i)Neo'
RETURN who;

#Did Keanu Reeves act in the movie Cloud Atlas?
MATCH (p:Person) WHERE p.name =~ '(?i)Keanu Reeves' 
MATCH (m:Movie)  WHERE m.title =~ '(?i)cloud atlas' 
RETURN exists((p) -[:ACTED_IN]-> (m)) AS answer;

#Who were acting in movie The Matrix?
MATCH (p:Person) -[r:ACTED_IN]-> (m:Movie)
WHERE m.title =~ '(?i)The Matrix'
RETURN p.name + ' acted as ' + r.roles[0] AS answer;

#Who directed movie The Matrix?
MATCH (p:Person) -[r:DIRECTED]-> (m:Movie)
WHERE m.title =~ '(?i)The Matrix'
RETURN p.name AS answer;

#Was Keanu Reeves the director of movie Cloud Atlas?
MATCH (p:Person) WHERE p.name =~ '(?i)Keanu Reeves' 
MATCH (m:Movie)  WHERE m.title =~ '(?i)cloud atlas' 
RETURN exists((p) -[:DIRECTED]-> (m)) AS answer;

#Who wrote movie Speed Racer?
MATCH (p:Person) -[:WROTE]-> (m:Movie)  WHERE m.title =~ '(?i)Speed Racer' 
RETURN p.name AS who;

#What are the movies Keanu Reeves acted in between 1990 and 2000?
MATCH (p:Person) -[:ACTED_IN]-> (m:Movie)
WHERE p.name =~ '(?i)Keanu Reeves' 
  AND m.released >= 1990 AND m.released <= 2000
RETURN m.title AS answer;


#I love Sleepless in Seattle, can you recommend a few other similar movies?
MATCH (m:Movie) <-[:ACTED_IN]- (p)
WHERE m.title =~ '(?i)Sleepless in Seattle'
WITH m, collect(p.name) AS actorsCol
MATCH (m1:Movie)  <-[:ACTED_IN]- (p1) WHERE m1 <> m
WITH m1.title AS title, collect(p1.name) AS actorsCol1, actorsCol
WITH title, toFloat(size(apoc.coll.intersection(actorsCol, actorsCol1))) / size(apoc.coll.union(actorsCol, actorsCol1)) AS similarity
RETURN title ORDER BY similarity DESC LIMIT 3;

#Who acted in movie Sleepless in Seattle other than Tom Hanks?
MATCH (p0:Person) -[:ACTED_IN]-> (m:Movie) <-[r:ACTED_IN]- (p)
WHERE m.title =~ '(?i)Sleepless in Seattle' AND p0.name =~ '(?)Tom Hanks'
RETURN p.name + ' acting as ' + r.roles[0] AS answer;

#`;

      //let search = "Tell me something about the movie The Matrix?";

      let query = training + search + "\n"

      let textToSpeak = ''
      try {
        console.log("query", query)
        if (search) {

          const response = await openai.createCompletion("davinci", {
            prompt: query,
            temperature: 0,
            max_tokens: 150,
            top_p: 1.0,
            frequency_penalty: 0.0,
            presence_penalty: 0.0,
            stop: ["#", ";"],
          });

          console.log('response:', response);
          let cypher = response.data.choices[0].text;
          console.log('MoviesBot:' + cypher);

          try {
            const result = await session.run(cypher)

            //const singleRecord = result.records[0]

            const records = result.records

            records.forEach(element => {
              textToSpeak += element.get(0) + ", "
            });

            //textToSpeak = singleRecord.get(0)
            textToSpeak = textToSpeak.slice(0, -2)

            console.log("records", records)
          } finally {
            //await session.close()
          }

          // on application exit:
          //await driver.close()
        }
      }
      catch (error) {
        //console.log(process.env);
        console.error(error)
        console.log('MoviesBot:' + textToSpeak);
        textToSpeak = "Sorry I can't answer that. Could you please try again?"
      }

      let isConfidential = false;
      if (textToSpeak.startsWith(CONFIDENTIAL)) {
        isConfidential = true;
        // textToSpeak = textToSpeak.substring(CONFIDENTIAL.length)
      }

      self.setState({ loading: false, result: textToSpeak });

      if (isConfidential || textToSpeak.length > 115) {
        speech.speak({ text: "Please find the information below" })
          .then(() => { console.log("Success !") })
          .catch(e => { console.error("An error occurred :", e) })
      } else {
        speech.speak({ text: textToSpeak })
          .then(() => { console.log("Success !") })
          .catch(e => { console.error("An error occurred :", e) })
      }

    }
    callAsync();
  }

  triggetNext() {
    this.setState({}, () => {
      this.props.triggerNextStep();
    });
  }

  componentDidMount() {
    this.callMoviesBot();
    this.triggetNext();
  }

  render() {
    const { loading, result } = this.state;
    const lines = result.split("\n");
    const elements = [];
    for (const [index, value] of lines.entries()) {
      elements.push(<span key={index}>{value}<br /></span>)
    }

    return (
      <div className="bot-response">
        {loading ? <Loading /> : elements}
      </div>
    );
  }
}

MoviesBot.propTypes = {
  steps: PropTypes.object,
  triggerNextStep: PropTypes.func,
};

MoviesBot.defaultProps = {
  steps: undefined,
  triggerNextStep: undefined,
};

export default MoviesBot;
