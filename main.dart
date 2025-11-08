import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';

// --- Data Model ---

// Enum to differentiate between user and AI messages
enum Sender { user, gemini }

// Simple class to hold message data
class Message {
  final String text;
  final Sender sender;
  final bool isGenerating;

  Message({
    required this.text,
    required this.sender,
    this.isGenerating = false,
  });
}

// --- Main Application Setup ---

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Using a dark theme for the modern, high-contrast look
        brightness: Brightness.dark,
        primarySwatch: Colors.cyan,
        scaffoldBackgroundColor: Colors.indigo.shade800,
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyan,
          secondary: Colors.tealAccent,
        ),
        // Custom text theme for better readability in dark mode
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
          titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        useMaterial3: true,
      ),
      home: const GeminiChatScreen(),
    );
  }
}

// --- Chat Screen and Logic ---

class GeminiChatScreen extends StatefulWidget {
  const GeminiChatScreen({super.key});

  @override
  State<GeminiChatScreen> createState() => _GeminiChatScreenState();
}

class _GeminiChatScreenState extends State<GeminiChatScreen> {
  final List<Message> _messages = <Message>[];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _lastWords = '';
  bool _isProcessingSpeech = false;

  FlutterTts flutterTts = FlutterTts();

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage("en-GB");
    await flutterTts.setPitch(2.0);
  }

  @override
  void initState() {
    super.initState();
    // 💡 Call the initialization function here
    _initSpeech();
    _initializeTts();
  }
  
  // Initial suggestions like those seen in the Gemini interface
  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  
  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  /// Each time to start a speech recognition session
  void _startListening() async {
  //if (_isProcessingSpeech) return; // Guard
  
  setState(() {
    _isProcessingSpeech = true;
  });

  await _speechToText.listen(onResult: _onSpeechResult);
  
  // Keep _isProcessingSpeech true until the session is stopped manually or automatically
  setState(() {}); 
}

void _stopListening() async {
  if (_speechToText.isNotListening) return; // Guard

  // Set the flag back to false only after the stop operation completes.
  await _speechToText.stop();
  
  _textController.text = _lastWords; 
  
  // 2. Reposition the cursor to the end of the newly inserted text
  _textController.selection = TextSelection.fromPosition(
    TextPosition(offset: _lastWords.length)
  );
  // 3. Clear the last words storage variable
  _lastWords = '';
  _isProcessingSpeech = false;
  setState(() {
    _isProcessingSpeech = false; // Reset flag after operation
  });

  // Automatically submit the recognized text (or let the user press send)
     _handleSubmitted(_textController.text);
}

  /// This is the callback that the SpeechToText plugin calls when
  /// the platform returns recognized words.
  void _onSpeechResult(SpeechRecognitionResult result) async {
    setState(() {
      _lastWords = result.recognizedWords;
    });
  }

  // Handles sending the message and simulating an AI response
  // Handles sending the message and getting an AI response via Flask
void _handleSubmitted(String text) async {
  if (text.trim().isEmpty || _isSending) return;

  // Store the original user text before clearing the controller
  final userQuery = text;

  setState(() {
    _isSending = true;
  });

  // 1. Add user message
  Message userMessage = Message(text: userQuery, sender: Sender.user);
  _messages.add(userMessage);
  _textController.clear();

  // 2. Simulate AI thinking (loading state)
  Message generatingMessage = Message(
      text: 'Generating response...',
      sender: Sender.gemini,
      isGenerating: true);
  _messages.add(generatingMessage);

  // Scroll to the bottom immediately after adding messages
  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

  String aiResponseText = "An error occurred. Could not connect to the server.";

  try {
    // ⚠️ IMPORTANT: Replace 10.71.134.197 with your **laptop's IP address**
    // (the one you found in the previous answer) or '10.0.2.2' if using an Android Emulator.
    final response = await http.post(
      Uri.parse("http://10.71.134.197:5000/ask"),   //copy the your adress ipv4 here
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"query": userQuery}),
    ).timeout(const Duration(seconds: 100)); // Add a timeout for reliability

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // Access the 'reply' key from the JSON response
      aiResponseText = data["reply"] ?? "Received an empty response.";
    } else {
      aiResponseText = "Server Error: Status ${response.statusCode}";
    }
  } catch (e) {
    // Catch connection errors, timeouts, and JSON parsing errors
    aiResponseText = "$e. Is the Flask server running at the correct IP and port? ($e)";
  }

  // 3. Update the UI with the final response
  setState(() {
    // Remove the generating message
    _messages.removeLast();
    // Add the final response
    _messages.add(Message(text: aiResponseText, sender: Sender.gemini));
    flutterTts.speak(aiResponseText);
    _isSending = false;
  });
  _scrollToBottom();
}

  // Utility to scroll the list view to the bottom
  void _scrollToBottom() async {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // --- UI Builders ---

  // Builds a single message bubble
  Widget _buildMessage(Message message) {
    final bool isUser = message.sender == Sender.user;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = isUser ? const Color.fromARGB(255, 5, 16, 136) : Colors.grey.shade900;
    final textColor = isUser ? Colors.white : Colors.white;

    // The AI response uses RichText to simulate markdown for bolding
    final List<TextSpan> textSpans = message.text.split('**').map((textPart) {
      final index = message.text.split('**').indexOf(textPart);
      final isBold = index % 2 != 0;
      return TextSpan(
        text: textPart,
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: textColor,
          fontSize: 15,
        ),
      );
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
      child: Align(
        alignment: alignment,
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isUser) // Optional icon for the AI
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0, left: 4.0),
                child: Text("Vit VDA", 
                style: TextStyle(color: Colors.white, 
                  fontSize: 20.0, 
                  fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16.0),
                  topRight: const Radius.circular(16.0),
                  bottomLeft: isUser
                      ? const Radius.circular(16.0)
                      : const Radius.circular(4.0),
                  bottomRight: isUser
                      ? const Radius.circular(4.0)
                      : const Radius.circular(16.0),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 5,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: message.isGenerating
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.tealAccent)),
                        const SizedBox(width: 8),
                        Text(message.text, style: TextStyle(color: textColor)),
                      ],
                    )
                  : RichText(text: TextSpan(children: textSpans)),
            ),
          ],
        ),
      ),
    );
  }

  // Builds the suggestions area when no messages are present
  Widget _buildSuggestions() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_fix_high, size: 60, color: Colors.cyan),
            const SizedBox(height: 16),
            Text(
              'Hello! How can I help you today?',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            
          ],
        ),
      ),
    );
  }

  // The main input field area
  Widget _buildMessageComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
      color: Colors.grey.shade900,
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Padding(padding: const EdgeInsets.only(right: 8.0),
            child: FloatingActionButton(
              onPressed:  _speechToText.isNotListening ? _startListening : _stopListening,
              tooltip: 'Listen',
              // Add padding for better touch target
              //padding: const EdgeInsets.all(10),
              //style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              child: Icon(_speechToText.isNotListening ? Icons.mic_off : Icons.mic,
                color: _textController.text.trim().isEmpty || _isSending
                  ? Colors.grey.shade700
                  : Colors.cyan
                ),
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(100.0),
                  border: Border.all(color: Colors.cyan.shade600),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: TextField(
                    controller: _textController,
                    onSubmitted: _handleSubmitted,
                    decoration: const InputDecoration.collapsed(
                      hintText: 'type or speak..',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    style: const TextStyle(color: Colors.white),
                    maxLines: null, // Allows multiline input
                    textInputAction: TextInputAction.send,
                    enabled: !_isSending,
                  ),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              child: IconButton(
                icon: Icon(Icons.send_rounded,
                    color: _textController.text.trim().isEmpty || _isSending
                        ? Colors.grey.shade700
                        : Colors.cyan),
                onPressed: _isSending
                    ? null
                    : () => _handleSubmitted(_textController.text),
                // Add padding for better touch target
                padding: const EdgeInsets.all(10),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VIT Digital Voice Assistant', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.cyan.shade700,
        shadowColor: Color(0),
        elevation: 200,
        centerTitle: false,
      ),
      body: Column(
        children: <Widget>[
          // Display suggestions if no messages exist, otherwise display the chat history
          Expanded(
            child: _messages.isEmpty
                ? _buildSuggestions()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessage(_messages[index]);
                    },
                  ),
          ),
          // Input composer at the bottom
          _buildMessageComposer(),
        ],
      ),
    );
  }
}