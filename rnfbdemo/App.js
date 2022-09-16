import React, { Component } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';
import firebase from '@react-native-firebase/app';
import auth from '@react-native-firebase/auth';
import firestore from '@react-native-firebase/firestore';

const instructions = Platform.select({
  ios: 'Press Cmd+R to reload,\n' + 'Cmd+D or shake for dev menu',
  android:
    'Double tap R on your keyboard to reload,\n' +
    'Shake or press menu button for dev menu',
});

export default class App extends Component {
  render() {
    return (
      <View style={styles.container}>
        <Text style={styles.welcome}>React Native Firebase Build Demo</Text>
        <Text style={styles.instructions}>To get started, edit App.js</Text>
        <Text />
        <Text style={styles.instructions}>{instructions}</Text>
        <Text />
        <Text>JSI Executor: {global.__jsiExecutorDescription}</Text>
        <Text />
        <Text>These firebase modules appear to be working:</Text>
        <Text />
        {firebase.apps.length && <Text style={styles.module}>app()</Text>}
        {auth().native && <Text style={styles.module}>auth()</Text>}
        {firestore().native && <Text style={styles.module}>firestore()</Text>}
      </View>
    );
  }
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#F5FCFF',
  },
  welcome: {
    fontSize: 20,
    textAlign: 'center',
    margin: 10,
  },
  instructions: {
    textAlign: 'center',
    color: '#333333',
    marginBottom: 5,
  },
});
