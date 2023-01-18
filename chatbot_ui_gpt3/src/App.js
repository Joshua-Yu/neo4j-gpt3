import './App.css';
import ChatBot from 'react-simple-chatbot';
import { ThemeProvider } from 'styled-components';
import MoviesBot from './component/moviesbot_gpt3';


const ENABLE_THEME = true

const theme_red = {
  background: '#f5f8fb',
  fontFamily: 'Tahoma',
  headerBgColor: '#0066ff',
  headerFontColor: '#fff',
  headerFontSize: '15px',
  botBubbleColor: '#3399ff',
  botFontColor: '#fff',
  userBubbleColor: '#fff',
  userFontColor: '#4a4a4a',
};

const theme = ENABLE_THEME ? theme_red : ''

const steps = [
  {
    id: 'bot-welcome',
    message: 'Welcome to MoviesBot, how can I help?',
    trigger: 'user'
  },
  {
    id: 'user',
    user: true,
    trigger: 'bot-response'
  },
  {
    id: 'bot-response',
    component: <MoviesBot />,
    waitAction: true,
    asMessage: true,
    trigger: 'user'
  },
  {
    id: 'not-bye',
    message: 'Thank you. Have a great day!',
    end: true
  },
];

function App() {
  let chatbot = <ChatBot
    steps={steps}
    headerTitle="MoviesBot"
    botAvatar="ai_trans.png"
    userAvatar="user.png"
    recognitionEnable={true}
    width="450px"
    speechSynthesis={{ enable: false, lang: 'en' }}
  />

  return (
    <div className="App" style={{display: 'flex', justifyContent: 'center'}}>
      {
         (theme !== '') ? <ThemeProvider theme={theme}> {chatbot} </ThemeProvider> : chatbot
      }
    </div>
  );
}

export default App;
