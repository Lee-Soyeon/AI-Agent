import { BottomNavigation, BottomNavigationItem } from '@montage-ui/core';
import { IconHome, IconHomeFill, IconSetting } from '@montage-ui/icon';
import { useState } from 'react';

import type { Recipe } from './catalog';
import { clientId } from './google';
import Confirm from './screens/Confirm';
import Home from './screens/Home';
import Login from './screens/Login';
import Onboarding from './screens/Onboarding';
import RecipeSteps from './screens/RecipeSteps';
import Settings from './screens/Settings';
import TaskView from './screens/TaskView';
import { type Account, type Profile, store } from './store';

type Route =
  | { name: 'home' }
  | { name: 'settings' }
  | { name: 'onboarding' }
  | { name: 'recipe'; recipe: Recipe }
  | { name: 'confirm'; prompt: string; title: string }
  | { name: 'task'; id: string };

export default function App() {
  const [account, setAccount] = useState<Account | null>(store.account);
  const [profile, setProfile] = useState<Profile | null>(store.profile);
  const [route, setRoute] = useState<Route>({ name: 'home' });

  const home = () => setRoute({ name: 'home' });

  // 클라이언트 ID 가 없는 빌드(로컬 개발)는 로그인 없이 쓴다.
  if (clientId && !account) {
    return (
      <div className="frame">
        <Login
          onSignIn={(a) => {
            store.setAccount(a);
            setAccount(a);
          }}
        />
      </div>
    );
  }

  if (!profile || route.name === 'onboarding') {
    return (
      <div className="frame">
        <Onboarding
          onDone={(p) => {
            store.setProfile(p);
            setProfile(p);
            home();
          }}
        />
      </div>
    );
  }

  const screen = (() => {
    switch (route.name) {
      case 'recipe':
        return (
          <RecipeSteps
            recipe={route.recipe}
            onBack={home}
            onDone={(prompt) => setRoute({ name: 'confirm', prompt, title: route.recipe.title })}
          />
        );
      case 'confirm':
        return (
          <Confirm
            title={route.title}
            prompt={route.prompt}
            onBack={home}
            onStarted={(id) => setRoute({ name: 'task', id })}
          />
        );
      case 'task':
        return <TaskView id={route.id} onBack={home} />;
      case 'settings':
        return (
          <Settings
            account={account}
            profile={profile}
            onEditProfile={() => setRoute({ name: 'onboarding' })}
            onSignOut={() => {
              store.setAccount(null);
              setAccount(null);
            }}
          />
        );
      default:
        return (
          <Home
            account={account}
            profile={profile}
            onRecipe={(recipe) => setRoute({ name: 'recipe', recipe })}
            onFree={(text) => setRoute({ name: 'confirm', prompt: text, title: '직접 맡기기' })}
          />
        );
    }
  })();

  const tab = route.name === 'settings' ? 'settings' : route.name === 'home' ? 'home' : null;

  return (
    <div className="frame">
      {screen}
      {tab && (
        <div className="tabbar">
          <BottomNavigation value={tab} onValueChange={(v) => setRoute(v === 'settings' ? { name: 'settings' } : { name: 'home' })}>
            <BottomNavigationItem value="home" label="홈" icon={tab === 'home' ? <IconHomeFill /> : <IconHome />} />
            <BottomNavigationItem value="settings" label="설정" icon={<IconSetting />} />
          </BottomNavigation>
        </div>
      )}
    </div>
  );
}
